(* CLI for OCaml inference that loads evolved programs with node budgets or fixed depth *)

open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Gp_tree_json
(* No need to open Expectimax_aligned *)

(* Search mode type *)
type search_mode = 
  | NodeBudget of int
  | FixedDepth of int

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
    let next_depth = depth - 1 in
    
    match empty_cells with
    | [] -> max_value_limited board program next_depth control
    | _ when next_depth < 0 -> eval_program program board
    | cells ->
      let num_empty = float_of_int (List.length cells) in
      let nodes_per_spawn = max 1 (control.nodes_remaining / (List.length cells * 2)) in
      
      let sum_score_2 = List.fold_left (fun acc cell_idx ->
        let board_with_2 = set_cell board cell_idx 1 in
        let local_control = { control with nodes_remaining = nodes_per_spawn } in
        acc +. max_value_limited board_with_2 program next_depth local_control
      ) 0.0 cells in
      
      let sum_score_4 = List.fold_left (fun acc cell_idx ->
        let board_with_4 = set_cell board cell_idx 2 in
        let local_control = { control with nodes_remaining = nodes_per_spawn } in
        acc +. max_value_limited board_with_4 program next_depth local_control
      ) 0.0 cells in
      
      (0.9 *. sum_score_2 +. 0.1 *. sum_score_4) /. num_empty
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
  
  match valid_moves with
  | [] -> None
  | _ ->
    let nodes_per_move = node_budget / List.length valid_moves in
    let max_depth = 10 in
    
    let move_values = List.map (fun dir ->
      let new_board = match dir with
        | `Up -> move_up board
        | `Down -> move_down board
        | `Left -> move_left board
        | `Right -> move_right board
      in
      let control = { nodes_remaining = nodes_per_move; max_depth_reached = 0 } in
      let value = expect_value_limited new_board program max_depth control in
      (dir, value, control.max_depth_reached)
    ) valid_moves in
    
    let best_move = List.fold_left (fun (best_dir, best_value, best_depth) (dir, value, depth) ->
      if value > best_value then (dir, value, depth) else (best_dir, best_value, best_depth)
    ) (List.hd move_values) (List.tl move_values) in
    
    Some (match best_move with (dir, _, _) -> dir)

(* Get best move using the specified search mode *)
let get_best_move_with_mode board program mode =
  match mode with
  | NodeBudget budget -> get_best_move_limited board program budget
  | FixedDepth depth -> Gp_2048_lib.Expectimax_aligned.get_best_move board program depth

(* Parse node budget from JSON string, defaulting to 500 *)
let parse_node_budget json_str =
  try
    (* Simple regex-like search for "node_budget": <number> *)
    let pattern = "\"node_budget\"[ ]*:[ ]*\\([0-9]+\\)" in
    let regex = Str.regexp pattern in
    if Str.string_match regex json_str 0 then
      int_of_string (Str.matched_group 1 json_str)
    else
      (* Search anywhere in the string *)
      try
        let _ = Str.search_forward regex json_str 0 in
        int_of_string (Str.matched_group 1 json_str)
      with Not_found -> 500
  with _ -> 500  (* Default on any error *)

(* Default simple program for testing *)
let default_program = {
  nodes = [| Add; NumEmptyCells; MaxTileValue |];
  fitness = 0.0;
  games_played = 0;
  avg_score = 0.0;
  avg_max_tile = 0.0;
}

let default_node_budget = 500

(* Convert direction to int for JSON output *)
let dir_to_int = function
  | `Up -> 0
  | `Down -> 1
  | `Left -> 2
  | `Right -> 3

(* Play a complete game and return trace *)

let play_complete_game program search_mode seed =
  let rng = Random.State.make [|seed|] in
  let board = ref 0x0000000000000000L in
  let score = ref 0 in
  let moves = ref [] in
  let move_count = ref 0 in
  
  (* Add initial tiles *)
  board := add_random_tile !board rng;
  board := add_random_tile !board rng;
  moves := `InitialBoard (!board, 0) :: !moves;
  
  (* Play game *)
  while not (is_game_over !board) && !move_count < 10000 do
    let best_move = get_best_move_with_mode !board program search_mode in
    match best_move with
    | None -> ()
    | Some dir ->
      let new_board = match dir with
        | `Up -> move_up !board
        | `Down -> move_down !board
        | `Left -> move_left !board
        | `Right -> move_right !board
      in
      
      if not (Int64.equal !board new_board) then begin
        let move_score = get_score_for_move !board dir in
        score := !score + move_score;
        board := new_board;
        board := add_random_tile !board rng;
        moves := `Move (dir_to_int dir, !board, move_score) :: !moves;
        incr move_count
      end else
        move_count := 10000  (* Force exit on illegal move *)
  done;
  
  (* Return trace in chronological order *)
  List.rev !moves, !score, get_max_tile !board, !move_count

(* Parse command line arguments *)
let parse_args () =
  let args = Array.to_list Sys.argv in
  let rec parse acc = function
    | [] -> acc
    | "--play-game" :: rest -> parse (("play-game", "true") :: acc) rest
    | "--node-budget" :: n :: rest -> parse (("node-budget", n) :: acc) rest
    | "--search-depth" :: n :: rest -> parse (("search-depth", n) :: acc) rest
    | file :: rest when String.length file >= 2 && String.sub file 0 2 <> "--" ->
        parse (("file", file) :: acc) rest
    | arg :: rest -> 
        if String.length arg >= 2 && String.sub arg 0 2 = "0x" then
          parse (("board", arg) :: acc) rest
        else
          parse (("seed", arg) :: acc) rest
  in
  parse [] (List.tl args)

let get_arg args key default =
  try List.assoc key args
  with Not_found -> default

let () =
  init_tables ();
  let args = parse_args () in
  
  (* Check for --play-game flag *)
  if get_arg args "play-game" "false" = "true" then begin
    (* Play complete game mode *)
    let model_file = get_arg args "file" "" in
    let seed = try int_of_string (get_arg args "seed" "42") with _ -> 42 in
    
    (* Load program *)
    let program, default_budget = 
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
    
    (* Determine search mode *)
    let search_mode = 
      match get_arg args "node-budget" "", get_arg args "search-depth" "" with
      | "", "" -> NodeBudget default_budget  (* Use model's default or 500 *)
      | n, "" -> NodeBudget (try int_of_string n with _ -> default_budget)
      | "", d -> FixedDepth (try int_of_string d with _ -> 2)
      | n, _ -> 
          (* If both specified, prefer node budget *)
          NodeBudget (try int_of_string n with _ -> default_budget)
    in
    
    (* Play game *)
    let start_time = Unix.gettimeofday () in
    let trace, final_score, max_tile, total_moves = play_complete_game program search_mode seed in
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
    
    (* Include search mode info *)
    (match search_mode with
    | NodeBudget b -> Printf.printf "\"node_budget\": %d" b
    | FixedDepth d -> Printf.printf "\"search_depth\": %d" d);
    Printf.printf "}\n";
    
  end else begin
    (* Single move mode *)
    let board_str = get_arg args "board" "" in
    if board_str = "" then begin
      Printf.eprintf "Usage: %s <board_hex> [model.json] [--node-budget N | --search-depth D]\n" Sys.argv.(0);
      Printf.eprintf "   or: %s --play-game [model.json] [seed] [--node-budget N | --search-depth D]\n" Sys.argv.(0);
      exit 1
    end;
    
    let board = Int64.of_string board_str in
    let model_file = get_arg args "file" "" in
    
    (* Load program and determine search mode *)
    let program, search_mode = 
      if model_file <> "" && Sys.file_exists model_file then
        try
          let ic = open_in model_file in
          let json_str = really_input_string ic (in_channel_length ic) in
          close_in ic;
          
          let program = load_program_from_json json_str in
          let default_budget = parse_node_budget json_str in
          
          let mode = match get_arg args "node-budget" "", get_arg args "search-depth" "" with
          | "", "" -> NodeBudget default_budget
          | n, "" -> NodeBudget (try int_of_string n with _ -> default_budget)
          | "", d -> FixedDepth (try int_of_string d with _ -> 2)
          | n, _ -> NodeBudget (try int_of_string n with _ -> default_budget)
          in
          (program, mode)
        with _ ->
          (default_program, NodeBudget default_node_budget)
      else
        (default_program, NodeBudget default_node_budget)
    in
    
    (* Time the inference *)
    let start_time = Unix.gettimeofday () in
    
    let move = match get_best_move_with_mode board program search_mode with
      | None -> -1
      | Some dir -> dir_to_int dir
    in
    
    let inference_time = Unix.gettimeofday () -. start_time in
    
    (* Output JSON with move, time, and search mode info *)
    Printf.printf "{\"move\": %d, \"inference_time_ms\": %.1f, " 
      move (inference_time *. 1000.0);
    
    (match search_mode with
    | NodeBudget b -> Printf.printf "\"node_budget\": %d" b
    | FixedDepth d -> Printf.printf "\"search_depth\": %d" d);
    Printf.printf "}\n"
  end