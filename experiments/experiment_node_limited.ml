open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree

(* Node-limited expectimax search *)
type search_control = {
  mutable nodes_remaining: int;
  mutable max_depth_reached: int;
}

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
    if empty_cells = [] then
      max_value_limited board program (depth - 1) control
    else
      let num_empty = List.length empty_cells in
      
      (* If too many empty cells or low on nodes, sample instead of full expansion *)
      let cells_to_try = 
        if num_empty > 6 && control.nodes_remaining < num_empty * 10 then
          (* Sample a subset *)
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
  
  (* Check valid moves *)
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
    (* Allocate nodes proportionally among valid moves *)
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
      
      (* Start with high depth limit, will be constrained by nodes *)
      let value = expect_value_limited new_board program 10 control in
      (dir, value, control.max_depth_reached)
    ) valid_moves in
    
    let best_move = List.fold_left (fun (best_dir, best_val, _) (dir, value, depth) ->
      if value > best_val then (dir, value, depth) else (best_dir, best_val, depth)
    ) (List.hd move_values) (List.tl move_values) in
    
    match best_move with
    | (dir, _, depth) -> Some (dir, depth)

(* Run experiments with different node budgets *)
let experiment_node_budgets () =
  Printf.printf "=== Node-Limited Expectimax Experiments ===\n\n";
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  let rng = Random.State.make [|42|] in
  
  (* Test different node budgets *)
  let node_budgets = [100; 500; 1000; 5000; 10000; 50000] in
  
  (* Create results file *)
  let oc = open_out "node_limited_results.txt" in
  Printf.fprintf oc "Node Budget | Avg Score | Max Score | Avg Max Tile | Games/sec | Avg Depth\n";
  Printf.fprintf oc "------------|-----------|-----------|--------------|-----------|----------\n";
  
  List.iter (fun budget ->
    Printf.printf "\nNode budget: %d\n" budget;
    flush stdout;
    
    let scores = ref [] in
    let max_tiles = ref [] in
    let total_time = ref 0.0 in
    let total_depth = ref 0 in
    let depth_count = ref 0 in
    
    (* Play 10 games *)
    for game = 1 to 10 do
      let start_time = Unix.gettimeofday () in
      let board = ref 0x0000000000000000L in
      let score = ref 0 in
      
      (* Add initial tiles *)
      board := add_random_tile !board rng;
      board := add_random_tile !board rng;
      
      (* Play game *)
      while not (is_game_over !board) do
        match get_best_move_limited !board simple_program budget with
        | None -> ()
        | Some (dir, depth) ->
          total_depth := !total_depth + depth;
          incr depth_count;
          
          let new_board = match dir with
            | `Up -> move_up !board
            | `Down -> move_down !board
            | `Left -> move_left !board
            | `Right -> move_right !board
          in
          
          let move_score = get_score_for_move !board dir in
          score := !score + move_score;
          board := new_board;
          board := add_random_tile !board rng
      done;
      
      let elapsed = Unix.gettimeofday () -. start_time in
      total_time := !total_time +. elapsed;
      
      let max_tile = get_max_tile !board in
      scores := !score :: !scores;
      max_tiles := max_tile :: !max_tiles;
      
      Printf.printf "  Game %d: score=%d, max_tile=2^%d, time=%.1fs\n" 
        game !score max_tile elapsed;
      flush stdout
    done;
    
    (* Calculate statistics *)
    let avg_score = (List.fold_left (+) 0 !scores) / 10 in
    let max_score = List.fold_left max 0 !scores in
    let avg_max_tile = (List.fold_left (+) 0 !max_tiles) / 10 in
    let games_per_sec = 10.0 /. !total_time in
    let avg_depth = if !depth_count > 0 then float_of_int !total_depth /. float_of_int !depth_count else 0.0 in
    
    Printf.printf "  Summary: avg_score=%d, max=%d, avg_tile=2^%d, speed=%.1f games/sec\n"
      avg_score max_score avg_max_tile games_per_sec;
    
    Printf.fprintf oc "%11d | %9d | %9d | %12d | %9.1f | %8.1f\n"
      budget avg_score max_score avg_max_tile games_per_sec avg_depth;
    flush oc
  ) node_budgets;
  
  close_out oc;
  Printf.printf "\nResults saved to node_limited_results.txt\n"

(* Test dynamic node allocation based on game state *)
let experiment_dynamic_nodes () =
  Printf.printf "\n\n=== Dynamic Node Allocation Experiment ===\n";
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  let rng = Random.State.make [|42|] in
  
  (* Different node allocation strategies *)
  let strategies = [
    ("Fixed 5000", fun _ _ -> 5000);
    ("Linear by empty", fun empty _ -> 500 + empty * 300);
    ("Exponential decay", fun empty _ -> 1000 * (1 lsl (min 4 (empty / 4))));
    ("Score-based", fun _ score -> 1000 + score / 100);
    ("Combined", fun empty score -> 
      let base = 1000 in
      let empty_bonus = empty * 200 in
      let score_bonus = min 5000 (score / 50) in
      base + empty_bonus + score_bonus
    );
  ] in
  
  Printf.printf "\nTesting different node allocation strategies (5 games each):\n";
  
  List.iter (fun (name, node_fn) ->
    Printf.printf "\nStrategy: %s\n" name;
    flush stdout;
    
    let total_score = ref 0 in
    let total_time = ref 0.0 in
    let max_tiles = ref [] in
    
    for game = 1 to 5 do
      let start_time = Unix.gettimeofday () in
      let board = ref 0x0000000000000000L in
      let score = ref 0 in
      
      board := add_random_tile !board rng;
      board := add_random_tile !board rng;
      
      while not (is_game_over !board) do
        let empty_count = List.length (get_empty_cells !board) in
        let node_budget = node_fn empty_count !score in
        
        match get_best_move_limited !board simple_program node_budget with
        | None -> ()
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
          board := add_random_tile !board rng
      done;
      
      let elapsed = Unix.gettimeofday () -. start_time in
      total_time := !total_time +. elapsed;
      total_score := !total_score + !score;
      max_tiles := get_max_tile !board :: !max_tiles;
      
      Printf.printf "  Game %d: score=%d, max_tile=2^%d\n" 
        game !score (get_max_tile !board);
      flush stdout
    done;
    
    let avg_score = !total_score / 5 in
    let avg_max_tile = (List.fold_left (+) 0 !max_tiles) / 5 in
    
    Printf.printf "  Average: score=%d, max_tile=2^%d, speed=%.1f games/sec\n"
      avg_score avg_max_tile (5.0 /. !total_time)
  ) strategies

(* Main *)
let () =
  init_tables ();
  experiment_node_budgets ();
  experiment_dynamic_nodes ()