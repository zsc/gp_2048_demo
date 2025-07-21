(* Expectimax with memoization for avoiding repeated evaluations *)

open Game
open Gp_tree

(* Cache module for storing board evaluations *)
module BoardCache = struct
  (* Key is (board, depth), value is evaluation score *)
  type t = (int64 * int, float) Hashtbl.t
  
  let create size = Hashtbl.create size
  
  let clear cache = Hashtbl.clear cache
  
  let stats cache = 
    let size = Hashtbl.length cache in
    size
    
  (* Make a key from board and depth *)
  let make_key board depth = (board, depth)
  
  (* Try to find a cached value *)
  let find_opt cache board depth = 
    Hashtbl.find_opt cache (make_key board depth)
    
  (* Add a value to cache *)
  let add cache board depth value =
    Hashtbl.add cache (make_key board depth) value;
    value
end

(* Global cache and statistics *)
let max_cache = BoardCache.create 100000
let expect_cache = BoardCache.create 100000
let cache_hits = ref 0
let cache_misses = ref 0

let reset_cache () =
  BoardCache.clear max_cache;
  BoardCache.clear expect_cache;
  cache_hits := 0;
  cache_misses := 0

let get_cache_stats () =
  let hit_rate = if !cache_hits + !cache_misses > 0 then
    float_of_int !cache_hits /. float_of_int (!cache_hits + !cache_misses) *. 100.0
  else 0.0 in
  (!cache_hits, !cache_misses, hit_rate, BoardCache.stats max_cache, BoardCache.stats expect_cache)

(* Memoized max_value function *)
let rec max_value board program depth =
  (* Check cache first *)
  match BoardCache.find_opt max_cache board depth with
  | Some value -> 
    incr cache_hits;
    value
  | None ->
    incr cache_misses;
    let value = 
      if is_game_over board then
        eval program board -. 1e6  (* Penalize game over states *)
      else if depth = 0 then
        eval program board
      else
        let moves = [
          move_up board;
          move_down board;
          move_left board;
          move_right board
        ] in
        
        let moved_boards = List.filter (fun new_board -> 
          not (Int64.equal board new_board)) moves in
        
        if List.length moved_boards = 0 then
          eval program board
        else
          let utilities = List.map (fun new_board ->
            expect_value new_board program depth
          ) moved_boards in
          List.fold_left max neg_infinity utilities
    in
    BoardCache.add max_cache board depth value

(* Memoized expect_value function *)
and expect_value board program depth =
  (* Check cache first *)
  match BoardCache.find_opt expect_cache board depth with
  | Some value ->
    incr cache_hits;
    value
  | None ->
    incr cache_misses;
    let value =
      let empty_cells = get_empty_cells board in
      let next_depth = depth - 1 in
      
      match empty_cells with
      | [] -> max_value board program next_depth
      | _ when next_depth < 0 -> eval program board
      | cells ->
        let num_empty = float_of_int (List.length cells) in
        
        (* Calculate sum of scores for adding '2' (90% probability) *)
        let sum_score_2 = List.fold_left (fun acc cell_idx ->
          let board_with_2 = set_cell board cell_idx 1 in  (* log2(2) = 1 *)
          acc +. max_value board_with_2 program next_depth
        ) 0.0 cells in
        
        (* Calculate sum of scores for adding '4' (10% probability) *)
        let sum_score_4 = List.fold_left (fun acc cell_idx ->
          let board_with_4 = set_cell board cell_idx 2 in  (* log2(4) = 2 *)
          acc +. max_value board_with_4 program next_depth
        ) 0.0 cells in
        
        (* Expected score = (0.9 * sum(scores_with_2) + 0.1 * sum(scores_with_4)) / num_empty *)
        (0.9 *. sum_score_2 +. 0.1 *. sum_score_4) /. num_empty
    in
    BoardCache.add expect_cache board depth value

(* Get the best move for a given board state *)
let get_best_move board program search_depth =
  (* Clear cache for new search to avoid stale data *)
  reset_cache ();
  
  let moves = [
    (`Up, move_up board);
    (`Down, move_down board);
    (`Left, move_left board);
    (`Right, move_right board)
  ] in
  
  let valid_moves = List.filter (fun (_, new_board) -> 
    not (Int64.equal board new_board)) moves in
  
  match valid_moves with
  | [] -> None
  | moves ->
    (* Find the move with highest expected value *)
    let scored_moves = List.map (fun (dir, new_board) ->
      let eval_score = expect_value new_board program search_depth in
      (dir, eval_score)
    ) moves in
    
    let best_move = List.fold_left (fun (best_dir, best_score) (dir, score) ->
      if score > best_score then (dir, score) else (best_dir, best_score)
    ) (List.hd scored_moves) (List.tl scored_moves) in
    
    Some (fst best_move)

(* Play a complete game using memoized expectimax *)
let play_game program rng search_depth max_moves =
  let rec play_loop board score moves =
    if moves >= max_moves then
      (score, get_max_tile board)
    else if is_game_over board then
      (score, get_max_tile board)
    else
      match get_best_move board program search_depth with
      | None -> (score, get_max_tile board)
      | Some direction ->
        let new_board = match direction with
          | `Up -> move_up board
          | `Down -> move_down board
          | `Left -> move_left board
          | `Right -> move_right board
        in
        let move_score = get_score_for_move board direction in
        let new_board = add_random_tile new_board rng in
        play_loop new_board (score + move_score) (moves + 1)
  in
  
  let initial_board = empty_board in
  let initial_board = add_random_tile initial_board rng in
  let initial_board = add_random_tile initial_board rng in
  play_loop initial_board 0 0

(* Evaluate fitness by playing multiple games *)
let evaluate_fitness program rng num_games search_depth max_moves =
  let total_score = ref 0.0 in
  let total_max_tile = ref 0.0 in
  
  for _ = 1 to num_games do
    let score, max_tile = play_game program rng search_depth max_moves in
    total_score := !total_score +. float_of_int score;
    total_max_tile := !total_max_tile +. float_of_int max_tile
  done;
  
  let avg_score = !total_score /. float_of_int num_games in
  let avg_max_tile = !total_max_tile /. float_of_int num_games in
  
  program.avg_score <- avg_score;
  program.avg_max_tile <- avg_max_tile;
  program.games_played <- num_games;
  program.fitness <- avg_score +. (avg_max_tile ** 2.0);
  
  program.fitness