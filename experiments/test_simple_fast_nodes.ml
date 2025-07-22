open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Domainslib

(* Global domain pool - default to 6 cores *)
let num_domains = ref 6
let pool = ref None

let get_pool () =
  match !pool with
  | Some p -> p
  | None ->
    let p = Task.setup_pool ~num_domains:!num_domains () in
    pool := Some p;
    p

(* Node-limited expectimax search - copied from experiment_node_limited.ml *)
type search_control = {
  mutable nodes_remaining: int;
  mutable max_depth_reached: int;
}

(* Dynamic depth mode *)
type depth_mode = 
  | Fixed of int
  | Dynamic of (int * int * int * int)  (* thresholds: t1, t2, t3, t4 *)

let get_dynamic_depth (t1, t2, t3, t4) empty_cells =
  if empty_cells >= t1 then 1
  else if empty_cells >= t2 then 2
  else if empty_cells >= t3 then 3
  else t4

let rec max_value_limited board program depth control =
  if control.nodes_remaining <= 0 then
    eval_program program board
  else begin
    control.nodes_remaining <- control.nodes_remaining - 1;
    control.max_depth_reached <- max control.max_depth_reached depth;
    
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

let get_best_move_limited board program node_budget depth_mode =
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
    let max_depth = match depth_mode with
      | Fixed d -> d
      | Dynamic params -> 
          let empty_cells = count_empty_cells board in
          get_dynamic_depth params empty_cells
    in
    
    (* Use parallel evaluation only if enough work per move *)
    let move_values = 
      if nodes_per_move >= 1000 && !num_domains > 1 then
        (* Parallel evaluation of moves *)
        let pool = get_pool () in
        Task.run pool (fun () ->
          let results = Array.make (List.length valid_moves) (List.hd valid_moves, neg_infinity, 0) in
          let valid_moves_arr = Array.of_list valid_moves in
          
          Task.parallel_for pool ~start:0 ~finish:(Array.length valid_moves_arr - 1) 
            ~body:(fun i ->
              let dir = valid_moves_arr.(i) in
              let new_board = match dir with
                | `Up -> move_up board
                | `Down -> move_down board
                | `Left -> move_left board
                | `Right -> move_right board
              in
              let control = { nodes_remaining = nodes_per_move; max_depth_reached = 0 } in
              let value = expect_value_limited new_board program max_depth control in
              results.(i) <- (dir, value, control.max_depth_reached)
            );
          Array.to_list results
        )
      else
        (* Sequential evaluation for small node budgets *)
        List.map (fun dir ->
          let new_board = match dir with
            | `Up -> move_up board
            | `Down -> move_down board
            | `Left -> move_left board
            | `Right -> move_right board
          in
          let control = { nodes_remaining = nodes_per_move; max_depth_reached = 0 } in
          let value = expect_value_limited new_board program max_depth control in
          (dir, value, control.max_depth_reached)
        ) valid_moves
    in
    
    let best_move = List.fold_left (fun (best_dir, best_value, best_depth) (dir, value, depth) ->
      if value > best_value then (dir, value, depth) else (best_dir, best_value, best_depth)
    ) (List.hd move_values) (List.tl move_values) in
    
    Some (match best_move with (dir, _, depth) -> (dir, depth))

(* Test simple_fast with different node budgets *)
let test_simple_fast_budgets ~num_games depth_mode =
  Printf.printf "=== Testing simple_fast (ADD EMPTY MAXTILE) with different node budgets ===\n";
  Printf.printf "Depth mode: %s\n" 
    (match depth_mode with
     | Fixed d -> Printf.sprintf "Fixed depth %d" d
     | Dynamic (t1, t2, t3, t4) -> Printf.sprintf "Dynamic (%d/%d/%d/%d)" t1 t2 t3 t4);
  Printf.printf "Using %d CPU cores for parallel evaluation\n" !num_domains;
  Printf.printf "Playing %d games per configuration\n\n" num_games;
  flush stdout;
  
  let simple_fast = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  (* Test these node budgets *)
  let budgets = [100; 500; 1000; 1500; 2000] in
  
  Printf.printf "Budget | Avg Score | Std Dev | Max Score | Min Score | Avg Tile | Max Tile | Games/sec\n";
  Printf.printf "-------|-----------|---------|-----------|-----------|----------|----------|----------\n";
  
  List.iter (fun budget ->
    let start_time = Unix.gettimeofday () in
    
    (* Play games in parallel *)
    let pool = get_pool () in
    let results = Task.run pool (fun () ->
      Task.parallel_for_reduce pool ~start:0 ~finish:(num_games - 1)
        ~body:(fun game_idx ->
          let rng = Random.State.make [|42 + game_idx * 13 + budget|] in
          let board = ref 0x0000000000000000L in
          let score = ref 0 in
          
          (* Add initial tiles *)
          board := add_random_tile !board rng;
          board := add_random_tile !board rng;
          
          (* Play game with node limit *)
          let moves = ref 0 in
          while not (is_game_over !board) && !moves < 1000000 do
            match get_best_move_limited !board simple_fast budget depth_mode with
            | None -> moves := 1000000  (* Force exit *)
            | Some (dir, _) ->
              let new_board = match dir with
                | `Up -> move_up !board
                | `Down -> move_down !board
                | `Left -> move_left !board
                | `Right -> move_right !board
              in
              
              let move_score = get_score_for_move !board dir in
              score := !score + move_score;
              board := new_board;
              board := add_random_tile !board rng;
              incr moves
          done;
          
          [(!score, get_max_tile !board)]
        )
        (fun acc lst -> acc @ lst)
        []
    ) in
    
    let elapsed = Unix.gettimeofday () -. start_time in
    let games_per_sec = float_of_int num_games /. elapsed in
    
    (* Calculate statistics *)
    let scores = List.map fst results in
    let tiles = List.map snd results in
    
    let avg_score = float_of_int (List.fold_left (+) 0 scores) /. float_of_int num_games in
    let max_score = List.fold_left max 0 scores in
    let min_score = List.fold_left min max_int scores in
    let avg_tile = float_of_int (List.fold_left (+) 0 tiles) /. float_of_int num_games in
    let max_tile = List.fold_left max 0 tiles in
    
    (* Standard deviation *)
    let variance = List.fold_left (fun acc s ->
      let diff = float_of_int s -. avg_score in
      acc +. (diff *. diff)
    ) 0.0 scores /. float_of_int num_games in
    let std_dev = sqrt variance in
    
    Printf.printf "%6d | %9.0f | %7.0f | %9d | %9d | %8.0f | %8d | %9.1f\n"
      budget avg_score std_dev max_score min_score avg_tile max_tile games_per_sec;
    flush stdout
  ) budgets;
  
  Printf.printf "\nExperiment completed!\n"

(* Test different dynamic depth configurations *)
let test_dynamic_depth_ablations ~num_games =
  Printf.printf "=== Dynamic Depth Ablation Study ===\n";
  Printf.printf "Using %d CPU cores for parallel evaluation\n" !num_domains;
  Printf.printf "Playing %d games per configuration\n\n" num_games;
  flush stdout;
  
  (* Test configurations: (t1, t2, t3, max_depth) *)
  let configurations = [
    (* Baseline - from experiment_dynamic_depth.ml *)
    ("Baseline (12/8/4/4)", (12, 8, 4, 4));
    
    (* Vary first threshold *)
    ("Early switch (14/8/4/4)", (14, 8, 4, 4));
    ("Late switch (10/8/4/4)", (10, 8, 4, 4));
    
    (* Vary second threshold *)
    ("Mid early (12/10/4/4)", (12, 10, 4, 4));
    ("Mid late (12/6/4/4)", (12, 6, 4, 4));
    
    (* Vary third threshold *)
    ("Deep early (12/8/6/4)", (12, 8, 6, 4));
    ("Deep late (12/8/2/4)", (12, 8, 2, 4));
    
    (* Vary max depth *)
    ("Deeper max (12/8/4/5)", (12, 8, 4, 5));
    ("Shallower max (12/8/4/3)", (12, 8, 4, 3));
    
    (* More aggressive *)
    ("Aggressive (14/10/6/3)", (14, 10, 6, 3));
    ("Conservative (10/6/2/5)", (10, 6, 2, 5));
  ] in
  
  (* Fixed node budget for all tests *)
  let node_budget = 1000 in
  
  Printf.printf "Config | Avg Score | Std Dev | Max Score | Min Score | Avg Tile | Max Tile | Games/sec\n";
  Printf.printf "-------|-----------|---------|-----------|-----------|----------|----------|----------\n";
  
  List.iter (fun (name, params) ->
    let start_time = Unix.gettimeofday () in
    let depth_mode = Dynamic params in
    
    (* Run games for this configuration *)
    let simple_fast = {
      nodes = [| Add; NumEmptyCells; MaxTileValue |];
      fitness = 0.0;
      games_played = 0;
      avg_score = 0.0;
      avg_max_tile = 0.0;
    } in
    
    (* Play games in parallel *)
    let pool = get_pool () in
    let results = Task.run pool (fun () ->
      Task.parallel_for_reduce pool ~start:0 ~finish:(num_games - 1)
        ~body:(fun game_idx ->
          let rng = Random.State.make [|42 + game_idx * 17 + Hashtbl.hash name|] in
          let board = ref 0x0000000000000000L in
          let score = ref 0 in
          
          (* Add initial tiles *)
          board := add_random_tile !board rng;
          board := add_random_tile !board rng;
          
          (* Play game with dynamic depth *)
          let moves = ref 0 in
          while not (is_game_over !board) && !moves < 1000000 do
            match get_best_move_limited !board simple_fast node_budget depth_mode with
            | None -> moves := 1000000  (* Force exit *)
            | Some (dir, _) ->
              let new_board = match dir with
                | `Up -> move_up !board
                | `Down -> move_down !board
                | `Left -> move_left !board
                | `Right -> move_right !board
              in
              
              let move_score = get_score_for_move !board dir in
              score := !score + move_score;
              board := new_board;
              board := add_random_tile !board rng;
              incr moves
          done;
          
          [(!score, get_max_tile !board)]
        )
        (fun acc lst -> acc @ lst)
        []
    ) in
    
    let elapsed = Unix.gettimeofday () -. start_time in
    let games_per_sec = float_of_int num_games /. elapsed in
    
    (* Calculate statistics *)
    let scores = List.map fst results in
    let tiles = List.map snd results in
    
    let avg_score = float_of_int (List.fold_left (+) 0 scores) /. float_of_int num_games in
    let max_score = List.fold_left max 0 scores in
    let min_score = List.fold_left min max_int scores in
    let avg_tile = float_of_int (List.fold_left (+) 0 tiles) /. float_of_int num_games in
    let max_tile = List.fold_left max 0 tiles in
    
    (* Standard deviation *)
    let variance = List.fold_left (fun acc s ->
      let diff = float_of_int s -. avg_score in
      acc +. (diff *. diff)
    ) 0.0 scores /. float_of_int num_games in
    let std_dev = sqrt variance in
    
    Printf.printf "%-22s | %9.0f | %7.0f | %9d | %9d | %8.0f | %8d | %9.1f\n"
      name avg_score std_dev max_score min_score avg_tile max_tile games_per_sec;
    flush stdout
  ) configurations;
  
  Printf.printf "\nDynamic depth ablation study completed!\n"

(* Cleanup function *)
let cleanup () =
  match !pool with
  | Some p -> Task.teardown_pool p
  | None -> ()

(* Main *)
let () =
  init_tables ();
  
  let args = Sys.argv in
  let num_games = ref 50 in
  
  if Array.length args <= 1 then begin
    Printf.printf "Usage: %s <cores> [games] [mode]\n" args.(0);
    Printf.printf "  cores: number of CPU cores to use\n";
    Printf.printf "  games: number of games per configuration (default: 50)\n";
    Printf.printf "  mode: 'fixed', 'dynamic', or 'ablation' (default: fixed)\n";
    Printf.printf "\nUsing defaults: %d cores, %d games, fixed mode\n\n" !num_domains !num_games;
  end;
  
  if Array.length args > 1 then begin
    try
      num_domains := int_of_string args.(1);
      Printf.printf "Using %d cores for parallel evaluation\n" !num_domains
    with _ ->
      Printf.printf "Invalid number of cores, using default %d\n" !num_domains
  end;
  
  if Array.length args > 2 then begin
    try
      num_games := int_of_string args.(2);
      Printf.printf "Playing %d games per configuration\n" !num_games
    with _ ->
      Printf.printf "Invalid number of games, using default %d\n" !num_games
  end;
  
  (* Check for mode flag *)
  let mode = if Array.length args > 3 then args.(3) else "fixed" in
  
  match mode with
  | "fixed" ->
      (* Original fixed depth mode *)
      test_simple_fast_budgets ~num_games:!num_games (Fixed 10);
  | "dynamic" ->
      (* Test with baseline dynamic depth *)
      test_simple_fast_budgets ~num_games:!num_games (Dynamic (12, 8, 4, 4));
  | "ablation" ->
      (* Run ablation study *)
      test_dynamic_depth_ablations ~num_games:!num_games;
  | _ ->
      Printf.printf "Unknown mode: %s\n" mode;
      Printf.printf "Valid modes: fixed, dynamic, ablation\n";
  
  (* Cleanup domain pool *)
  cleanup ()