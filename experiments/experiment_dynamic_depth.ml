open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree

(* Track search statistics *)
type search_stats = {
  mutable nodes_visited: int;
  mutable time_spent: float;
}

(* Modified expectimax with node counting *)
let rec max_value_counted board program depth stats =
  stats.nodes_visited <- stats.nodes_visited + 1;
  
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
        let value = expect_value_counted new_board program depth stats in
        max best_value value
      ) neg_infinity valid_moves

and expect_value_counted board program depth stats =
  stats.nodes_visited <- stats.nodes_visited + 1;
  
  let empty_cells = get_empty_cells board in
  if empty_cells = [] then
    max_value_counted board program (depth - 1) stats
  else
    let num_empty = List.length empty_cells in
    let sum = List.fold_left (fun acc pos ->
      let board_2 = set_cell board pos 1 in
      let board_4 = set_cell board pos 2 in
      acc +. 0.9 *. max_value_counted board_2 program (depth - 1) stats
          +. 0.1 *. max_value_counted board_4 program (depth - 1) stats
    ) 0.0 empty_cells in
    sum /. float_of_int num_empty

(* Experiment 1: Profile search performance by empty cells *)
let profile_search_by_empty_cells () =
  Printf.printf "\n=== Experiment 1: Search Performance by Empty Cells ===\n";
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  (* Test boards with different numbers of empty cells *)
  let test_cases = [
    (0x0000000000000000L, 16, "Empty board");
    (0x0000000000001234L, 12, "4 tiles");
    (0x1234567800000000L, 8, "8 tiles");
    (0x123456789ABC0000L, 4, "12 tiles");
    (0x123456789ABCDEF0L, 1, "15 tiles");
  ] in
  
  List.iter (fun depth ->
    Printf.printf "\nDepth %d:\n" depth;
    Printf.printf "Empty Cells | Nodes | Time(ms) | Nodes/sec\n";
    Printf.printf "------------|-------|----------|----------\n";
    
    List.iter (fun (board, empty_count, _) ->
      let stats = { nodes_visited = 0; time_spent = 0.0 } in
      let start = Unix.gettimeofday () in
      
      let _ = max_value_counted board simple_program depth stats in
      
      let elapsed = Unix.gettimeofday () -. start in
      stats.time_spent <- elapsed;
      
      Printf.printf "%11d | %5d | %8.1f | %9.0f\n"
        empty_count stats.nodes_visited (elapsed *. 1000.0)
        (float_of_int stats.nodes_visited /. elapsed);
      flush stdout
    ) test_cases
  ) [1; 2; 3; 4]

(* Dynamic depth strategy based on empty cells *)
let get_dynamic_depth empty_cells =
  if empty_cells >= 12 then 1
  else if empty_cells >= 8 then 2
  else if empty_cells >= 4 then 3
  else 4

(* Node-limited search strategy *)
let get_depth_for_node_limit empty_cells node_limit =
  (* Estimate nodes based on branching factor *)
  (* Roughly: 4 moves * empty_cells * 2 tile values *)
  let branching_factor = float_of_int (4 * empty_cells * 2) in
  
  (* Find depth that keeps nodes under limit *)
  let rec find_depth d =
    let estimated_nodes = branching_factor ** float_of_int d in
    if estimated_nodes > float_of_int node_limit || d > 6 then d - 1
    else find_depth (d + 1)
  in
  max 1 (find_depth 1)

(* Experiment 2: Compare different depth strategies *)
let compare_depth_strategies () =
  Printf.printf "\n\n=== Experiment 2: Depth Strategy Comparison ===\n";
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  let rng = Random.State.make [|42|] in
  
  (* Different strategies *)
  let strategies = [
    ("Fixed Depth 1", fun _ -> 1);
    ("Fixed Depth 2", fun _ -> 2);
    ("Fixed Depth 3", fun _ -> 3);
    ("Dynamic (12/8/4)", get_dynamic_depth);
    ("Node Limited 10k", fun ec -> get_depth_for_node_limit ec 10000);
    ("Node Limited 50k", fun ec -> get_depth_for_node_limit ec 50000);
  ] in
  
  List.iter (fun (name, depth_fn) ->
    Printf.printf "\n%s:\n" name;
    flush stdout;
    
    let total_score = ref 0 in
    let total_moves = ref 0 in
    let total_time = ref 0.0 in
    let total_nodes = ref 0 in
    let max_tiles = ref [] in
    
    (* Play 5 games *)
    for game = 1 to 5 do
      let board = ref 0x0000000000000000L in
      let score = ref 0 in
      let moves = ref 0 in
      let game_nodes = ref 0 in
      let start = Unix.gettimeofday () in
      
      (* Add initial tiles *)
      board := add_random_tile !board rng;
      board := add_random_tile !board rng;
      
      (* Play game *)
      while not (is_game_over !board) do
        let empty_count = List.length (get_empty_cells !board) in
        let depth = depth_fn empty_count in
        let stats = { nodes_visited = 0; time_spent = 0.0 } in
        
        (* Find best move *)
        let best_dir = ref None in
        let best_value = ref neg_infinity in
        
        List.iter (fun dir ->
          let new_board = match dir with
            | `Up -> move_up !board
            | `Down -> move_down !board
            | `Left -> move_left !board
            | `Right -> move_right !board
          in
          
          if not (Int64.equal !board new_board) then begin
            let value = expect_value_counted new_board simple_program depth stats in
            if value > !best_value then begin
              best_value := value;
              best_dir := Some dir
            end
          end
        ) [`Up; `Down; `Left; `Right];
        
        game_nodes := !game_nodes + stats.nodes_visited;
        
        match !best_dir with
        | None -> moves := 1000  (* Force exit *)
        | Some dir ->
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
      
      let elapsed = Unix.gettimeofday () -. start in
      let max_tile = get_max_tile !board in
      
      total_score := !total_score + !score;
      total_moves := !total_moves + !moves;
      total_time := !total_time +. elapsed;
      total_nodes := !total_nodes + !game_nodes;
      max_tiles := max_tile :: !max_tiles;
      
      Printf.printf "  Game %d: score=%d, moves=%d, max_tile=2^%d, nodes=%d\n"
        game !score !moves max_tile !game_nodes;
      flush stdout
    done;
    
    let avg_score = !total_score / 5 in
    let avg_moves = !total_moves / 5 in
    let avg_nodes = !total_nodes / 5 in
    let avg_max_tile = (List.fold_left (+) 0 !max_tiles) / 5 in
    
    Printf.printf "  Average: score=%d, moves=%d, max_tile=2^%d\n" 
      avg_score avg_moves avg_max_tile;
    Printf.printf "  Performance: %.1f games/sec, %d nodes/game\n"
      (5.0 /. !total_time) avg_nodes;
    flush stdout
  ) strategies

(* Experiment 3: Adaptive node budget *)
let test_adaptive_node_budget () =
  Printf.printf "\n\n=== Experiment 3: Adaptive Node Budget ===\n";
  Printf.printf "Testing time-based node allocation...\n\n";
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  let rng = Random.State.make [|42|] in
  
  (* Time budgets in ms per move *)
  let time_budgets = [10.0; 50.0; 100.0; 200.0] in
  
  List.iter (fun budget_ms ->
    Printf.printf "Time budget: %.0fms per move\n" budget_ms;
    
    let board = ref 0x0000000000000000L in
    let score = ref 0 in
    let moves = ref 0 in
    
    board := add_random_tile !board rng;
    board := add_random_tile !board rng;
    
    (* Play until game over *)
    while not (is_game_over !board) do
      let empty_count = List.length (get_empty_cells !board) in
      let move_start = Unix.gettimeofday () in
      
      (* Start with depth 1 and increase until time budget *)
      let best_move = ref None in
      let depth = ref 1 in
      
      while Unix.gettimeofday () -. move_start < budget_ms /. 1000.0 && !depth <= 6 do
        let stats = { nodes_visited = 0; time_spent = 0.0 } in
        let best_value = ref neg_infinity in
        let best_dir = ref None in
        
        List.iter (fun dir ->
          let new_board = match dir with
            | `Up -> move_up !board
            | `Down -> move_down !board
            | `Left -> move_left !board
            | `Right -> move_right !board
          in
          
          if not (Int64.equal !board new_board) then begin
            let value = expect_value_counted new_board simple_program !depth stats in
            if value > !best_value then begin
              best_value := value;
              best_dir := Some dir
            end
          end
        ) [`Up; `Down; `Left; `Right];
        
        if !best_dir <> None then best_move := !best_dir;
        incr depth
      done;
      
      match !best_move with
      | None -> moves := 1000
      | Some dir ->
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
        incr moves;
        
        if !moves mod 10 = 0 then begin
          Printf.printf "  Move %d: score=%d, empty=%d, depth=%d\n" 
            !moves !score empty_count (!depth - 1);
          flush stdout
        end
    done;
    
    Printf.printf "  Final: score=%d, max_tile=2^%d\n\n" 
      !score (get_max_tile !board);
    flush stdout
  ) time_budgets

(* Main *)
let () =
  init_tables ();
  profile_search_by_empty_cells ();
  compare_depth_strategies ();
  test_adaptive_node_budget ()