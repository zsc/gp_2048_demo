(* CLI for OCaml inference that loads evolved programs with node budgets *)

open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Gp_tree_json

(* Node-limited expectimax *)
type search_control = {
  mutable nodes_remaining: int;
  mutable max_depth_reached: int;
}

let rec max_value_limited board program depth control =
  if control.nodes_remaining <= 0 then
    eval_program program board
  else begin
    control.nodes_remaining <- control.nodes_remaining - 1;
    
    if is_game_over board then
      eval_program program board -. 1000000.0
    else if depth = 0 then
      eval_program program board
    else
      let moves = [`Up; `Down; `Left; `Right] in
      let valid_moves = List.filter (fun dir ->
        let new_board = match dir with
          | `Up -> move_up board
          | `Down -> move_down board
          | `Left -> move_left board
          | `Right -> move_right board
        in
        not (Int64.equal board new_board)
      ) moves in
      
      if valid_moves = [] then
        eval_program program board -. 1000000.0
      else
        List.fold_left (fun best_value dir ->
          let new_board = match dir with
            | `Up -> move_up board
            | `Down -> move_down board
            | `Left -> move_left board
            | `Right -> move_right board
          in
          let value = expect_value_limited new_board program depth control in
          max best_value value
        ) neg_infinity valid_moves
  end

and expect_value_limited board program depth control =
  if control.nodes_remaining <= 0 then
    eval_program program board
  else begin
    control.nodes_remaining <- control.nodes_remaining - 1;
    
    let empty_cells = get_empty_cells board in
    if empty_cells = [] then
      max_value_limited board program (depth - 1) control
    else
      let num_empty = List.length empty_cells in
      let cells_to_try = 
        if num_empty > 6 && control.nodes_remaining < num_empty * 10 then
          let n = min 4 num_empty in
          let rec take n lst =
            match n, lst with
            | 0, _ | _, [] -> []
            | n, h::t -> h :: take (n-1) t
          in
          take n empty_cells
        else
          empty_cells
      in
      
      let sum = List.fold_left (fun acc pos ->
        let board_2 = set_cell board pos 1 in
        let board_4 = set_cell board pos 2 in
        acc +. 0.9 *. max_value_limited board_2 program (depth - 1) control
            +. 0.1 *. max_value_limited board_4 program (depth - 1) control
      ) 0.0 cells_to_try in
      sum /. float_of_int (List.length cells_to_try)
  end

let get_best_move_limited board program node_budget =
  let moves = [`Up; `Down; `Left; `Right] in
  let valid_moves = List.filter (fun dir ->
    let new_board = match dir with
      | `Up -> move_up board
      | `Down -> move_down board
      | `Left -> move_left board
      | `Right -> move_right board
    in
    not (Int64.equal board new_board)
  ) moves in
  
  if valid_moves = [] then None
  else
    let nodes_per_move = node_budget / List.length valid_moves in
    let move_values = List.map (fun dir ->
      let new_board = match dir with
        | `Up -> move_up board
        | `Down -> move_down board
        | `Left -> move_left board
        | `Right -> move_right board
      in
      let control = { 
        nodes_remaining = nodes_per_move; 
        max_depth_reached = 0 
      } in
      let value = expect_value_limited new_board program 10 control in
      (dir, value)
    ) valid_moves in
    
    let best_move = List.fold_left (fun (best_dir, best_val) (dir, value) ->
      if value > best_val then (dir, value) else (best_dir, best_val)
    ) (List.hd move_values) (List.tl move_values) in
    
    Some (fst best_move)

(* Default program if no model specified *)
let default_program = {
  nodes = [| Add; Mul; MonotonicityScore; SmoothnessScore; NumEmptyCells |];
  fitness = 0.0;
  games_played = 0;
  avg_score = 0.0;
  avg_max_tile = 0.0;
}

(* Default node budget *)
let default_node_budget = 1000

(* Parse node budget from JSON *)
let parse_node_budget json_str =
  try
    (* Look for "node_budget_max": number *)
    let key = "\"node_budget_max\":" in
    let idx = String.index json_str '"' in
    let rec find_key i =
      if i + String.length key > String.length json_str then raise Not_found
      else if String.sub json_str i (String.length key) = key then i + String.length key
      else find_key (i + 1)
    in
    let start = find_key idx in
    let rec find_end i =
      if i >= String.length json_str then i
      else if json_str.[i] = ',' || json_str.[i] = '}' then i
      else find_end (i + 1)
    in
    let finish = find_end start in
    int_of_string (String.trim (String.sub json_str start (finish - start)))
  with _ -> default_node_budget

(* Play a complete game and return trace *)
let play_complete_game program node_budget seed =
  let rng = Random.State.make [|seed|] in
  let moves = ref [] in
  let board = ref 0L in
  let score = ref 0 in
  
  (* Add initial tiles *)
  board := add_random_tile !board rng;
  board := add_random_tile !board rng;
  
  (* Record initial state *)
  moves := [`InitialBoard (!board, 0)] @ !moves;
  
  (* Play game *)
  let move_count = ref 0 in
  while not (is_game_over !board) && !move_count < 10000 do
    match get_best_move_limited !board program node_budget with
    | None -> ()
    | Some dir ->
      let old_board = !board in
      let new_board = match dir with
        | `Up -> move_up !board
        | `Down -> move_down !board
        | `Left -> move_left !board
        | `Right -> move_right !board
      in
      
      if not (Int64.equal old_board new_board) then begin
        let move_score = get_score_for_move !board dir in
        score := !score + move_score;
        board := new_board;
        board := add_random_tile !board rng;
        
        (* Record move *)
        let dir_int = match dir with
          | `Up -> 0 | `Down -> 1 | `Left -> 2 | `Right -> 3
        in
        moves := (`Move (dir_int, !board, move_score)) :: !moves;
        incr move_count
      end
  done;
  
  (* Return trace in chronological order *)
  List.rev !moves, !score, get_max_tile !board, !move_count

let () =
  init_tables ();
  
  (* Check for --play-game flag *)
  if Array.length Sys.argv >= 2 && Sys.argv.(1) = "--play-game" then begin
    (* Play complete game mode *)
    let model_file, seed = 
      if Array.length Sys.argv >= 3 then
        (Sys.argv.(2), if Array.length Sys.argv >= 4 then int_of_string Sys.argv.(3) else 42)
      else
        ("", 42)
    in
    
    (* Load program and node budget *)
    let program, node_budget = 
      if model_file <> "" && Sys.file_exists model_file then
        try
          let ic = open_in model_file in
          let json_str = really_input_string ic (in_channel_length ic) in
          close_in ic;
          let program = load_program_from_json json_str in
          let budget = parse_node_budget json_str in
          (program, budget)
        with _ ->
          (default_program, default_node_budget)
      else
        (default_program, default_node_budget)
    in
    
    (* Play game *)
    let start_time = Unix.gettimeofday () in
    let trace, final_score, max_tile, total_moves = play_complete_game program node_budget seed in
    let total_time = Unix.gettimeofday () -. start_time in
    
    (* Output JSON trace *)
    Printf.printf "{\"trace\": [";
    List.iteri (fun i move ->
      if i > 0 then Printf.printf ", ";
      match move with
      | `InitialBoard (board, _) ->
        Printf.printf "{\"type\": \"init\", \"board\": \"0x%Lx\"}" board
      | `Move (dir, board, score) ->
        Printf.printf "{\"type\": \"move\", \"direction\": %d, \"board\": \"0x%Lx\", \"score\": %d}"
          dir board score
    ) trace;
    Printf.printf "], ";
    Printf.printf "\"final_score\": %d, " final_score;
    Printf.printf "\"max_tile\": %d, " max_tile;
    Printf.printf "\"total_moves\": %d, " total_moves;
    Printf.printf "\"time_ms\": %.1f, " (total_time *. 1000.0);
    Printf.printf "\"node_budget\": %d}\n" node_budget;
    
  end else begin
    (* Single move mode *)
    if Array.length Sys.argv < 2 then begin
      Printf.eprintf "Usage: %s <board_hex> [model.json]\n" Sys.argv.(0);
      Printf.eprintf "   or: %s --play-game [model.json] [seed]\n" Sys.argv.(0);
      exit 1
    end;
    
    let board = Int64.of_string Sys.argv.(1) in
  
  (* Load program and node budget from JSON if provided *)
  let program, node_budget = 
    if Array.length Sys.argv > 2 then
      try
        let model_file = Sys.argv.(2) in
        let ic = open_in model_file in
        let json_str = really_input_string ic (in_channel_length ic) in
        close_in ic;
        
        let program = load_program_from_json json_str in
        let budget = parse_node_budget json_str in
        (program, budget)
      with _ ->
        (default_program, default_node_budget)
    else
      (default_program, default_node_budget)
  in
  
  (* Time the inference *)
  let start_time = Unix.gettimeofday () in
  
  let move = match get_best_move_limited board program node_budget with
    | None -> -1
    | Some dir ->
      match dir with
      | `Up -> 0
      | `Down -> 1
      | `Left -> 2
      | `Right -> 3
  in
  
  let inference_time = Unix.gettimeofday () -. start_time in
  
    (* Output JSON with move, time, and node budget used *)
    Printf.printf "{\"move\": %d, \"time_ms\": %.1f, \"node_budget\": %d}\n" 
      move (inference_time *. 1000.0) node_budget
  end