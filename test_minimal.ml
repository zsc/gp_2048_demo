open Gp_2048_lib.Game
open Gp_2048_lib.Random_tape

let () =
  (* Simple test with controlled random tape *)
  let tape = load_random_tape "test_controlled.txt" in
  
  (* Initial empty board *)
  let board = ref empty_board in
  
  (* Add two initial tiles *)
  board := add_random_tile_from_tape !board tape;
  Printf.printf "After tile 1: %016Lx\n" !board;
  
  board := add_random_tile_from_tape !board tape;
  Printf.printf "After tile 2: %016Lx\n" !board;
  
  (* Make a move *)
  board := move_left !board;
  Printf.printf "After left move: %016Lx\n" !board;
  
  (* Add another tile *)
  board := add_random_tile_from_tape !board tape;
  Printf.printf "After tile 3: %016Lx\n" !board;
  
  Printf.printf "Tape position used: %d\n" tape.index