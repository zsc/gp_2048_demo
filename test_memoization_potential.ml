open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned

(* Track board evaluations to measure duplication *)
let eval_count = Hashtbl.create 10000
let total_evals = ref 0

(* Wrapper around eval to count evaluations *)
let eval_counting program board =
  incr total_evals;
  let key = board in
  let count = match Hashtbl.find_opt eval_count key with
    | Some n -> n + 1
    | None -> 1
  in
  Hashtbl.replace eval_count key count;
  eval program board

(* Modified expectimax that counts evaluations *)
let rec max_value_counting board program depth =
  if is_game_over board then
    eval_counting program board -. 1e6
  else if depth = 0 then
    eval_counting program board
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
      eval_counting program board
    else
      let utilities = List.map (fun new_board ->
        expect_value_counting new_board program depth
      ) moved_boards in
      List.fold_left max neg_infinity utilities

and expect_value_counting board program depth =
  let empty_cells = get_empty_cells board in
  let next_depth = depth - 1 in
  
  match empty_cells with
  | [] -> max_value_counting board program next_depth
  | _ when next_depth < 0 -> eval_counting program board
  | cells ->
    let num_empty = float_of_int (List.length cells) in
    
    let sum_score_2 = List.fold_left (fun acc cell_idx ->
      let board_with_2 = set_cell board cell_idx 1 in
      acc +. max_value_counting board_with_2 program next_depth
    ) 0.0 cells in
    
    let sum_score_4 = List.fold_left (fun acc cell_idx ->
      let board_with_4 = set_cell board cell_idx 2 in
      acc +. max_value_counting board_with_4 program next_depth
    ) 0.0 cells in
    
    (0.9 *. sum_score_2 +. 0.1 *. sum_score_4) /. num_empty

let analyze_one_move board program depth =
  Hashtbl.clear eval_count;
  total_evals := 0;
  
  (* Evaluate all 4 moves *)
  let moves = [
    (`Up, move_up board);
    (`Down, move_down board);
    (`Left, move_left board);
    (`Right, move_right board)
  ] in
  
  let valid_moves = List.filter (fun (_, new_board) -> 
    not (Int64.equal board new_board)) moves in
  
  List.iter (fun (dir, new_board) ->
    let _ = expect_value_counting new_board program depth in
    ()
  ) valid_moves;
  
  (* Analyze duplication *)
  let duplicates = ref 0 in
  let max_count = ref 0 in
  Hashtbl.iter (fun _ count ->
    if count > 1 then incr duplicates;
    if count > !max_count then max_count := count
  ) eval_count;
  
  Printf.printf "Depth %d analysis:\n" depth;
  Printf.printf "  Total evaluations: %d\n" !total_evals;
  Printf.printf "  Unique boards: %d\n" (Hashtbl.length eval_count);
  Printf.printf "  Boards evaluated multiple times: %d\n" !duplicates;
  Printf.printf "  Max evaluation count for one board: %d\n" !max_count;
  Printf.printf "  Duplication rate: %.1f%%\n\n" 
    (float_of_int (!total_evals - Hashtbl.length eval_count) /. float_of_int !total_evals *. 100.0)

let () =
  init_tables ();
  
  (* Create a sample program *)
  let program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  (* Test with a mid-game board *)
  let rng = Random.State.make [|42|] in
  let board = ref empty_board in
  
  (* Build a realistic mid-game position *)
  for _ = 1 to 20 do
    board := add_random_tile !board rng;
    if Random.State.int rng 4 = 0 then
      board := move_up !board
    else if Random.State.int rng 4 = 1 then
      board := move_down !board
    else if Random.State.int rng 4 = 2 then
      board := move_left !board
    else
      board := move_right !board
  done;
  
  Printf.printf "Testing expectimax duplication on a mid-game board...\n\n";
  
  (* Test different search depths *)
  for depth = 1 to 4 do
    analyze_one_move !board program depth
  done