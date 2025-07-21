(* Test alignment of expectimax implementation *)

open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned

(* Simple evaluation function - count empty cells *)
let _simple_eval board =
  float_of_int (count_empty_cells board)

(* Create a simple program that just counts empty cells *)
let simple_program = {
  nodes = [| NumEmptyCells |];
  fitness = 0.0;
  games_played = 0;
  avg_score = 0.0;
  avg_max_tile = 0.0;
}

let test_basic_expectimax () =
  Printf.printf "Testing OCaml Expectimax Implementation\n";
  Printf.printf "==================================================\n";
  
  let test_boards = [
    Int64.of_string "0x0000000000001234";  (* Simple board *)
    Int64.of_string "0x1234567890ABCDEF";  (* Complex board *)
    Int64.of_string "0x0000000000000000";  (* Empty board *)
  ] in
  
  List.iter (fun board ->
    Printf.printf "\nBoard: %016Lx\n" board;
    
    (* Test max_value at different depths *)
    List.iter (fun depth ->
      let value = max_value board simple_program depth in
      Printf.printf "  max_value(depth=%d): %.2f\n" depth value
    ) [0; 1; 2];
    
    (* Test best move *)
    match get_best_move board simple_program 2 with
    | None -> Printf.printf "  best_move(depth=2): None\n"
    | Some dir ->
      let dir_str = match dir with
        | `Up -> "up"
        | `Down -> "down"
        | `Left -> "left"
        | `Right -> "right"
      in
      (* Calculate the score by evaluating the move *)
      let new_board = match dir with
        | `Up -> move_up board
        | `Down -> move_down board
        | `Left -> move_left board
        | `Right -> move_right board
      in
      let score = expect_value new_board simple_program 2 in
      Printf.printf "  best_move(depth=2): %s (score: %.2f)\n" dir_str score
  ) test_boards

let test_deterministic_game () =
  Printf.printf "\n\nTesting Deterministic Game Sequence\n";
  Printf.printf "==================================================\n";
  
  (* More sophisticated evaluation *)
  let eval_program = {
    nodes = [| Add; Mul; NumEmptyCells; Constant 10.0; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  (* Start with a specific board *)
  let initial_board = Int64.of_string "0x0000000000001122" in
  Printf.printf "Initial board: %016Lx\n" initial_board;
  
  (* Make a few moves *)
  let board = ref initial_board in
  for i = 1 to 3 do
    match get_best_move !board eval_program 2 with
    | None -> 
      Printf.printf "No valid moves!\n";
      ()
    | Some dir ->
      let dir_str = match dir with
        | `Up -> "up"
        | `Down -> "down"
        | `Left -> "left"
        | `Right -> "right"
      in
      
      (* Calculate expected score *)
      let new_board = match dir with
        | `Up -> move_up !board
        | `Down -> move_down !board
        | `Left -> move_left !board
        | `Right -> move_right !board
      in
      let expected_score = expect_value new_board eval_program 2 in
      Printf.printf "\nMove %d: %s (expected score: %.2f)\n" i dir_str expected_score;
      
      (* Execute the move *)
      let move_score = get_score_for_move !board dir in
      board := new_board;
      Printf.printf "After move: %016Lx (actual score: %d)\n" !board move_score
  done

let () =
  test_basic_expectimax ();
  test_deterministic_game ()