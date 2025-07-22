(* Benchmark comparison for OCaml implementation *)

open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned
open Gp_2048_lib.Random_tape

(* Simple program that evaluates to NumEmptyCells + MaxTileValue *)
let simple_program = {
  nodes = [| Add; NumEmptyCells; MaxTileValue |];
  fitness = 0.0;
  games_played = 0;
  avg_score = 0.0;
  avg_max_tile = 0.0;
}


let benchmark_expectimax initial_board num_iterations search_depth =
  let start_time = Unix.gettimeofday () in
  
  let value = ref 0.0 in
  for _ = 1 to num_iterations do
    (* Just compute the value, no actual moves *)
    value := max_value initial_board simple_program search_depth
  done;
  
  let end_time = Unix.gettimeofday () in
  let elapsed = end_time -. start_time in
  (elapsed, !value)

let benchmark_game_with_tape initial_board tape num_moves search_depth =
  let start_time = Unix.gettimeofday () in
  
  let board = ref initial_board in
  let score = ref 0 in
  let moves_made = ref 0 in
  
  (* Add initial tiles *)
  let event1 = get_next_event tape in
  board := add_tile_with_event !board event1;
  let event2 = get_next_event tape in
  board := add_tile_with_event !board event2;
  
  (* Play game *)
  for _ = 1 to num_moves do
    if is_game_over !board then
      ()
    else
      match get_best_move !board simple_program search_depth with
      | None -> ()
      | Some dir ->
        let new_board = match dir with
          | `Up -> move_up !board
          | `Down -> move_down !board
          | `Left -> move_left !board
          | `Right -> move_right !board
        in
        
        if Int64.equal !board new_board then
          ()
        else begin
          let move_score = get_score_for_move !board dir in
          score := !score + move_score;
          board := new_board;
          incr moves_made;
          
          (* Add random tile from tape *)
          let event = get_next_event tape in
          board := add_tile_with_event !board event
        end
  done;
  
  let end_time = Unix.gettimeofday () in
  let elapsed = end_time -. start_time in
  (elapsed, !board, !score, !moves_made)

let main () =
  Printf.printf "OCaml Benchmark\n";
  Printf.printf "==================================================\n";
  
  (* Test boards *)
  let test_boards = [
    (0x0000000000000000L, "empty");
    (0x0000000000001234L, "simple");
    (0x1234567890ABCDEFL, "complex");
  ] in
  
  (* Benchmark expectimax *)
  Printf.printf "\nExpectimax Benchmark (100 iterations):\n";
  List.iter (fun (board, name) ->
    List.iter (fun depth ->
      let elapsed, value = benchmark_expectimax board 100 depth in
      Printf.printf "  %s board, depth %d: %.3fs (value: %.2f)\n" 
        name depth elapsed value
    ) [1; 2]
  ) test_boards;
  
  (* Benchmark game with tape *)
  Printf.printf "\nGame Benchmark with Tape:\n";
  let tape = load_random_tape "test_tape.txt" in
  
  List.iter (fun depth ->
    reset_tape tape;  (* Reset tape for each test *)
    let elapsed, final_board, score, moves = 
      benchmark_game_with_tape 0x0000000000000000L tape 50 depth in
    Printf.printf "  Depth %d: %.3fs\n" depth elapsed;
    Printf.printf "    Final board: %016Lx\n" final_board;
    Printf.printf "    Score: %d, Moves: %d\n" score moves
  ) [1; 2]

let () = main ()