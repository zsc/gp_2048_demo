open Game
open Gp_tree

let rec gp_max_value board program depth =
  if is_game_over board then
    eval program board -. 1e7
  else if depth = 0 then
    eval program board
  else
    let moves = [
      (`Left, move_left board);
      (`Right, move_right board);
      (`Up, move_up board);
      (`Down, move_down board)
    ] in
    
    let valid_moves = List.filter (fun (_, new_board) -> 
      not (Int64.equal board new_board)) moves in
    
    if List.length valid_moves = 0 then
      eval program board -. 1e7
    else
      let utilities = List.map (fun (_, new_board) ->
        gp_expect_value new_board program depth
      ) valid_moves in
      List.fold_left max neg_infinity utilities

and gp_expect_value board program depth =
  let empty_cells = get_empty_cells board in
  match empty_cells with
  | [] -> eval program board
  | cells ->
    let total_utility = List.fold_left (fun acc cell_idx ->
      let board_with_2 = set_cell board cell_idx 1 in
      let board_with_4 = set_cell board cell_idx 2 in
      
      let utility_2 = 0.9 *. gp_max_value board_with_2 program (depth - 1) in
      let utility_4 = 0.1 *. gp_max_value board_with_4 program (depth - 1) in
      
      acc +. utility_2 +. utility_4
    ) 0.0 cells in
    
    total_utility /. float_of_int (List.length cells)

let get_best_move board program depth =
  let moves = [
    (`Left, move_left board);
    (`Right, move_right board);
    (`Up, move_up board);
    (`Down, move_down board)
  ] in
  
  let valid_moves = List.filter (fun (_, new_board) -> 
    not (Int64.equal board new_board)) moves in
  
  match valid_moves with
  | [] -> None
  | moves ->
    let scored_moves = List.map (fun (dir, new_board) ->
      let utility = gp_expect_value new_board program depth in
      (dir, utility)
    ) moves in
    
    let best_move = List.fold_left (fun (best_dir, best_util) (dir, util) ->
      if util > best_util then (dir, util) else (best_dir, best_util)
    ) (List.hd scored_moves) (List.tl scored_moves) in
    
    Some (fst best_move)

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
          | `Left -> move_left board
          | `Right -> move_right board
          | `Up -> move_up board
          | `Down -> move_down board
        in
        let move_score = get_score_for_move board direction in
        let new_board = add_random_tile new_board rng in
        play_loop new_board (score + move_score) (moves + 1)
  in
  
  let initial_board = empty_board in
  let initial_board = add_random_tile initial_board rng in
  let initial_board = add_random_tile initial_board rng in
  play_loop initial_board 0 0

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