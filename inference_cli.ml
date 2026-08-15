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
  stats: search_stats;
}

and search_stats = {
  mutable calls: int;
  mutable expanded: int;
  mutable cutoffs: int;
}

let make_search_stats () = { calls = 0; expanded = 0; cutoffs = 0 }

let rec max_value_limited board program depth control =
  control.stats.calls <- control.stats.calls + 1;
  if control.nodes_remaining <= 0 then
    begin
      control.stats.cutoffs <- control.stats.cutoffs + 1;
      eval_program program board
    end
  else begin
    control.nodes_remaining <- control.nodes_remaining - 1;
    control.stats.expanded <- control.stats.expanded + 1;
    
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
  control.stats.calls <- control.stats.calls + 1;
  if control.nodes_remaining <= 0 then
    begin
      control.stats.cutoffs <- control.stats.cutoffs + 1;
      eval_program program board
    end
  else begin
    control.nodes_remaining <- control.nodes_remaining - 1;
    control.stats.expanded <- control.stats.expanded + 1;
    
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

let get_best_move_limited_with_stats board program node_budget =
  let stats = make_search_stats () in
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
  | [] -> (None, stats)
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
      let control = {
        nodes_remaining = nodes_per_move;
        max_depth_reached = 0;
        stats;
      } in
      let value = expect_value_limited new_board program max_depth control in
      (dir, value, control.max_depth_reached)
    ) valid_moves in
    
    let best_move = List.fold_left (fun (best_dir, best_value, best_depth) (dir, value, depth) ->
      if value > best_value then (dir, value, depth) else (best_dir, best_value, best_depth)
    ) (List.hd move_values) (List.tl move_values) in
    
    (Some (match best_move with (dir, _, _) -> dir), stats)

let get_best_move_limited board program node_budget =
  fst (get_best_move_limited_with_stats board program node_budget)

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

type fpga_game_summary = {
  game_id: int;
  seed: int32;
  moves: int;
  score: int;
  max_tile: int;
  won_2048: bool;
  final_board: int64;
  search_seconds: float;
}

let fpga_lfsr_next value =
  let bit index =
    Int32.(to_int (logand (shift_right_logical value index) 1l))
  in
  let feedback = bit 31 lxor bit 21 lxor bit 1 lxor bit 0 in
  let result = Int32.logor (Int32.shift_left value 1) (Int32.of_int feedback) in
  if Int32.equal result 0l then 1l else result

let fpga_game_seed base_seed game_id =
  Int32.logxor base_seed
    (Int32.mul 0x9e3779b9l (Int32.of_int game_id))

(* Match the tournament RTL: exact 90/10 tile distribution and uniform empty
   cell selection using four-bit rejection sampling. *)
let fpga_add_random_tile board random_state =
  let rec choose_tile state =
    let next = fpga_lfsr_next state in
    let candidate = Int32.(to_int (logand next 0xfl)) in
    if candidate < 10 then
      (if candidate = 0 then 2 else 1), next
    else
      choose_tile next
  in
  let rec choose_cell state empty_count =
    let next = fpga_lfsr_next state in
    let candidate = Int32.(to_int (logand next 0xfl)) in
    let limit = (16 / empty_count) * empty_count in
    if candidate < limit then candidate mod empty_count, next
    else choose_cell next empty_count
  in
  match get_empty_cells board with
  | [] -> board, random_state, -1, 0
  | empty_cells ->
      let tile_value, after_tile = choose_tile random_state in
      let rank, after_cell = choose_cell after_tile (List.length empty_cells) in
      let cell = List.nth empty_cells rank in
      set_cell board cell tile_value, after_cell, cell, tile_value

let simulate_fpga_game program node_budget base_seed game_id =
  let seed = fpga_game_seed base_seed game_id in
  let random_state = ref (if Int32.equal seed 0l then 1l else seed) in
  let board = ref 0L in
  let score = ref 0 in
  let moves = ref 0 in
  let search_seconds = ref 0.0 in
  let add_tile () =
    let next_board, next_random, _, _ =
      fpga_add_random_tile !board !random_state
    in
    board := next_board;
    random_state := next_random
  in
  add_tile ();
  add_tile ();
  while not (is_game_over !board) && !moves < 10000 do
    let started = Unix.gettimeofday () in
    let best_move = get_best_move_limited !board program node_budget in
    search_seconds := !search_seconds +. (Unix.gettimeofday () -. started);
    match best_move with
    | None -> moves := 10000
    | Some direction ->
        let moved = match direction with
          | `Up -> move_up !board
          | `Down -> move_down !board
          | `Left -> move_left !board
          | `Right -> move_right !board
        in
        if Int64.equal moved !board then
          moves := 10000
        else begin
          score := !score + get_score_for_move !board direction;
          board := moved;
          add_tile ();
          incr moves
        end
  done;
  let max_tile = get_max_tile !board in
  {
    game_id;
    seed;
    moves = !moves;
    score = !score;
    max_tile;
    won_2048 = max_tile >= 2048;
    final_board = !board;
    search_seconds = !search_seconds;
  }

let simulate_fpga_games program node_budget base_seed game_count =
  let started = Unix.gettimeofday () in
  let wins = ref 0 in
  let total_moves = ref 0 in
  let total_score = ref 0 in
  let total_search_seconds = ref 0.0 in
  let max_tile_seen = ref 0 in
  let tile_counts = Hashtbl.create 8 in
  for game_id = 0 to game_count - 1 do
    let result = simulate_fpga_game program node_budget base_seed game_id in
    if result.won_2048 then incr wins;
    total_moves := !total_moves + result.moves;
    total_score := !total_score + result.score;
    total_search_seconds := !total_search_seconds +. result.search_seconds;
    max_tile_seen := max !max_tile_seen result.max_tile;
    Hashtbl.replace tile_counts result.max_tile
      (1 + Option.value (Hashtbl.find_opt tile_counts result.max_tile) ~default:0);
    Printf.printf
      "GAME game=%d seed=%08lx moves=%d score=%d max_tile=%d won_2048=%d final_board=%016Lx search_ms=%.3f\n"
      result.game_id result.seed result.moves result.score result.max_tile
      (if result.won_2048 then 1 else 0) result.final_board
      (result.search_seconds *. 1000.0);
    flush stdout
  done;
  let elapsed = Unix.gettimeofday () -. started in
  let tile_summary =
    Hashtbl.to_seq tile_counts |> List.of_seq
    |> List.sort (fun (left, _) (right, _) -> compare left right)
    |> List.map (fun (tile, count) -> Printf.sprintf "%d:%d" tile count)
    |> String.concat ","
  in
  Printf.printf
    "TOURNAMENT games=%d budget=%d wins_2048=%d win_rate=%.6f avg_moves=%.3f avg_score=%.3f max_tile=%d tile_counts=%s total_search_ms=%.3f wall_ms=%.3f\n"
    game_count node_budget !wins
    (float_of_int !wins /. float_of_int (max 1 game_count))
    (float_of_int !total_moves /. float_of_int (max 1 game_count))
    (float_of_int !total_score /. float_of_int (max 1 game_count))
    !max_tile_seen tile_summary (!total_search_seconds *. 1000.0)
    (elapsed *. 1000.0)

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

(* Emit legal in-game boards plus the exact node-limited golden result.  This is
   deliberately tied to the default evaluator implemented by the FPGA core. *)
let emit_search_vectors node_budget seed limit =
  let rng = Random.State.make [|seed|] in
  let board = ref 0x0000000000000000L in
  let emitted = ref 0 in
  let search_seconds = ref 0.0 in
  board := add_random_tile !board rng;
  board := add_random_tile !board rng;
  while not (is_game_over !board) && !emitted < limit do
    let search_start = Unix.gettimeofday () in
    let best_move, stats = get_best_move_limited_with_stats
      !board default_program node_budget in
    search_seconds := !search_seconds +.
      (Unix.gettimeofday () -. search_start);
    match best_move with
    | None -> emitted := limit
    | Some dir ->
      Printf.printf "%016Lx %d %d %d %d\n"
        !board (dir_to_int dir) stats.calls stats.expanded stats.cutoffs;
      let moved = match dir with
        | `Up -> move_up !board
        | `Down -> move_down !board
        | `Left -> move_left !board
        | `Right -> move_right !board
      in
      board := add_random_tile moved rng;
      incr emitted
  done;
  flush stdout;
  Printf.eprintf "VECTOR_BENCH count=%d total_search_ms=%.3f avg_search_us=%.3f\n"
    !emitted (!search_seconds *. 1000.0)
    (!search_seconds *. 1_000_000.0 /. float_of_int (max 1 !emitted))

(* Parse command line arguments *)
let parse_args () =
  let args = Array.to_list Sys.argv in
  let rec parse acc = function
    | [] -> acc
    | "--play-game" :: rest -> parse (("play-game", "true") :: acc) rest
    | "--simulate-games" :: n :: rest -> parse (("simulate-games", n) :: acc) rest
    | "--emit-vectors" :: n :: rest -> parse (("emit-vectors", n) :: acc) rest
    | "--node-budget" :: n :: rest -> parse (("node-budget", n) :: acc) rest
    | "--search-depth" :: n :: rest -> parse (("search-depth", n) :: acc) rest
    | arg :: rest when String.length arg >= 2 && String.sub arg 0 2 = "0x" ->
        parse (("board", arg) :: acc) rest
    | file :: rest when Filename.check_suffix file ".json" ->
        parse (("file", file) :: acc) rest
    | arg :: rest -> parse (("seed", arg) :: acc) rest
  in
  parse [] (List.tl args)

let get_arg args key default =
  try List.assoc key args
  with Not_found -> default

let () =
  init_tables ();
  let args = parse_args () in
  
  if get_arg args "simulate-games" "" <> "" then begin
    let game_count =
      try int_of_string (get_arg args "simulate-games" "64") with _ -> 64
    in
    let node_budget =
      try int_of_string (get_arg args "node-budget" "500") with _ -> 500
    in
    let base_seed =
      try Int32.of_string (get_arg args "seed" "0x2048c0de")
      with _ -> 0x2048c0del
    in
    simulate_fpga_games default_program node_budget base_seed game_count

  (* Generate a parity corpus for RTL simulation. *)
  end else if get_arg args "emit-vectors" "" <> "" then begin
    let limit = try int_of_string (get_arg args "emit-vectors" "64") with _ -> 64 in
    let seed = try int_of_string (get_arg args "seed" "42") with _ -> 42 in
    let node_budget =
      try int_of_string (get_arg args "node-budget" "500") with _ -> 500
    in
    emit_search_vectors node_budget seed limit

  (* Check for --play-game flag *)
  end else if get_arg args "play-game" "false" = "true" then begin
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
      Printf.eprintf "   or: %s --emit-vectors N [seed] [--node-budget N]\n" Sys.argv.(0);
      Printf.eprintf "   or: %s --simulate-games N [seed] [--node-budget N]\n" Sys.argv.(0);
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
    
    let move, stats = match search_mode with
      | NodeBudget budget ->
          let result, stats = get_best_move_limited_with_stats board program budget in
          ((match result with None -> -1 | Some dir -> dir_to_int dir), Some stats)
      | FixedDepth depth ->
          let result = Gp_2048_lib.Expectimax_aligned.get_best_move board program depth in
          ((match result with None -> -1 | Some dir -> dir_to_int dir), None)
    in
    
    let inference_time = Unix.gettimeofday () -. start_time in
    
    (* Output JSON with move, time, and search mode info *)
    Printf.printf "{\"move\": %d, \"time_ms\": %.3f, \"inference_time_ms\": %.3f, "
      move (inference_time *. 1000.0) (inference_time *. 1000.0);
    
    (match search_mode with
    | NodeBudget b -> Printf.printf "\"node_budget\": %d" b
    | FixedDepth d -> Printf.printf "\"search_depth\": %d" d);
    (match stats with
    | None -> ()
    | Some stats ->
        Printf.printf ", \"search_calls\": %d, \"expanded_nodes\": %d, \"cutoffs\": %d"
          stats.calls stats.expanded stats.cutoffs);
    Printf.printf "}\n"
  end
