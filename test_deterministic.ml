(* Test deterministic gameplay using external random tape *)

open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax
open Gp_2048_lib.Random_tape

(* Modified expectimax that uses tape instead of RNG *)
let play_game_with_tape program tape search_depth max_moves =
  
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
        let new_board = add_random_tile_from_tape new_board tape in
        play_loop new_board (score + move_score) (moves + 1)
  in
  
  let initial_board = empty_board in
  let initial_board = add_random_tile_from_tape initial_board tape in
  let initial_board = add_random_tile_from_tape initial_board tape in
  play_loop initial_board 0 0

let _print_board board =
  for row = 0 to 3 do
    for col = 0 to 3 do
      let value = get_cell board (row * 4 + col) in
      if value = 0 then
        Printf.printf "   . "
      else
        Printf.printf "%4d " (1 lsl value)
    done;
    Printf.printf "\n"
  done;
  Printf.printf "\n"

let test_with_tape tape_file =
  Printf.printf "Loading random tape from %s...\n" tape_file;
  let tape = load_random_tape tape_file in
  Printf.printf "Loaded %d random events\n\n" (Array.length tape.events);
  
  (* Create a simple test program *)
  let nodes = [|
    Mul;
    Add;
    NumEmptyCells;
    MonotonicityScore;
    SmoothnessScore
  |] in
  let program = { 
    nodes; 
    fitness = 0.0; 
    games_played = 0; 
    avg_score = 0.0; 
    avg_max_tile = 0.0 
  } in
  
  Printf.printf "Test program: %s\n\n" (program_to_string program);
  
  (* Play game with tape *)
  Printf.printf "Playing game with deterministic random tape...\n";
  let score, max_tile = play_game_with_tape program tape 2 100 in
  
  Printf.printf "\nGame complete!\n";
  Printf.printf "Final score: %d\n" score;
  Printf.printf "Max tile: %d\n" max_tile;
  Printf.printf "Random events used: %d\n" tape.index

let () =
  match Sys.argv with
  | [|_; tape_file|] -> test_with_tape tape_file
  | _ -> 
    Printf.printf "Usage: %s <random_tape.txt>\n" Sys.argv.(0);
    exit 1