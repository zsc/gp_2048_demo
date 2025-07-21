open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned

(* Score-based dynamic node allocation *)
let score_based_strategy () =
  Printf.printf "Testing Score-based Dynamic Node Allocation\n";
  Printf.printf "==========================================\n\n";
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  let rng = Random.State.make [|42|] in
  
  (* Score-based node allocation function *)
  let get_node_budget score =
    1000 + score / 100
  in
  
  (* Play one game *)
  let board = ref 0x0000000000000000L in
  let score = ref 0 in
  let moves = ref 0 in
  
  board := add_random_tile !board rng;
  board := add_random_tile !board rng;
  
  Printf.printf "Starting game...\n";
  
  while not (is_game_over !board) && !moves < 1000 do
    let node_budget = get_node_budget !score in
    
    match get_best_move !board simple_program 2 with
    | None -> moves := 1001
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
      
      if !moves mod 100 = 0 then begin
        Printf.printf "Move %d: score=%d, nodes=%d\n" !moves !score node_budget;
        flush stdout
      end
  done;
  
  let max_tile = get_max_tile !board in
  Printf.printf "\nGame Over!\n";
  Printf.printf "Final score: %d\n" !score;
  Printf.printf "Total moves: %d\n" !moves;
  Printf.printf "Max tile: 2^%d\n" max_tile;
  Printf.printf "\nThis demonstrates the score-based dynamic node allocation strategy.\n"

let () = 
  init_tables ();
  score_based_strategy ()