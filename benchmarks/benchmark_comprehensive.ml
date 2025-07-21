open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned

let time_it f =
  let start = Unix.gettimeofday () in
  let result = f () in
  let elapsed = Unix.gettimeofday () -. start in
  (result, elapsed)

let benchmark_board_operations iterations =
  Printf.printf "\n1. BOARD OPERATIONS BENCHMARK\n";
  Printf.printf "==================================================\n";
  
  let boards = [
    0x0000000000000000L;  (* empty *)
    0x0000000000001234L;  (* simple *)
    0x1234567890ABCDEFL;  (* complex *)
  ] in
  
  let total_time = ref 0.0 in
  
  List.iter (fun board ->
    let _, elapsed = time_it (fun () ->
      for _ = 1 to iterations do
        let _ = move_left board in
        let _ = move_right board in
        let _ = move_up board in
        let _ = move_down board in
        ()
      done
    ) in
    total_time := !total_time +. elapsed;
    Printf.printf "  Board %016Lx: %.3fs for %d moves\n" 
      board elapsed (iterations * 4)
  ) boards;
  
  let total_moves = List.length boards * iterations * 4 in
  Printf.printf "  Total: %.3fs for %d moves\n" !total_time total_moves;
  Printf.printf "  Speed: %.0f moves/sec\n" 
    (float_of_int total_moves /. !total_time)

let benchmark_gp_tree_evaluation iterations =
  Printf.printf "\n2. GP TREE EVALUATION BENCHMARK\n";
  Printf.printf "==================================================\n";
  
  (* Create a sample GP tree *)
  let rng = Random.State.make [|42|] in
  let tree = create_random_program rng 5 in
  
  let boards = [
    0x0000000000000000L;
    0x0000000000001234L;
    0x1234567890ABCDEFL;
  ] in
  
  let total_time = ref 0.0 in
  
  List.iter (fun board ->
    let _, elapsed = time_it (fun () ->
      for _ = 1 to iterations do
        let _ = eval_program tree board in
        ()
      done
    ) in
    total_time := !total_time +. elapsed;
    Printf.printf "  Board %016Lx: %.3fs for %d evaluations\n" 
      board elapsed iterations
  ) boards;
  
  let total_evals = List.length boards * iterations in
  Printf.printf "  Total: %.3fs for %d evaluations\n" !total_time total_evals;
  Printf.printf "  Speed: %.0f evals/sec\n" 
    (float_of_int total_evals /. !total_time)

let benchmark_expectimax iterations =
  Printf.printf "\n3. EXPECTIMAX SEARCH BENCHMARK\n";
  Printf.printf "==================================================\n";
  
  let boards = [
    0x0000000000000000L;
    0x0000000000001234L;
    0x1234567890ABCDEFL;
  ] in
  
  (* Simple evaluation program *)
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  List.iter (fun depth ->
    Printf.printf "\n  Depth %d:\n" depth;
    let total_time = ref 0.0 in
    
    List.iter (fun board ->
      let _, elapsed = time_it (fun () ->
        for _ = 1 to iterations do
          let _ = max_value board simple_program depth in
          ()
        done
      ) in
      total_time := !total_time +. elapsed;
      Printf.printf "    Board %016Lx: %.3fs\n" board elapsed
    ) boards;
    
    let total_searches = List.length boards * iterations in
    Printf.printf "    Total: %.3fs for %d searches\n" !total_time total_searches;
    if !total_time > 0.0 then
      Printf.printf "    Speed: %.1f searches/sec\n" 
        (float_of_int total_searches /. !total_time)
  ) [1; 2; 3]

let benchmark_full_game num_games =
  Printf.printf "\n4. FULL GAME BENCHMARK\n";
  Printf.printf "==================================================\n";
  
  let rng = Random.State.make [|42|] in
  
  (* Simple evaluation program *)
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  List.iter (fun depth ->
    let total_score = ref 0 in
    let total_moves = ref 0 in
    let games_played = ref 0 in
    
    let _, elapsed = time_it (fun () ->
      for _ = 1 to num_games do
        let initial_board = empty_board in
        let board1 = add_random_tile initial_board rng in
        let board2 = add_random_tile board1 rng in
        
        let rec play_moves board score moves =
          if moves >= 100 || is_game_over board then
            (score, moves)
          else
            match get_best_move board simple_program depth with
            | None -> (score, moves)
            | Some dir ->
                let new_board = match dir with
                  | `Up -> move_up board
                  | `Down -> move_down board
                  | `Left -> move_left board
                  | `Right -> move_right board
                in
                if Int64.equal board new_board then
                  (score, moves)
                else
                  let move_score = get_score_for_move board dir in
                  let board_with_tile = add_random_tile new_board rng in
                  play_moves board_with_tile (score + move_score) (moves + 1)
        in
        
        let score, moves = play_moves board2 0 0 in
        total_score := !total_score + score;
        total_moves := !total_moves + moves;
        incr games_played
      done
    ) in
    
    let avg_score = float_of_int !total_score /. float_of_int num_games in
    let avg_moves = float_of_int !total_moves /. float_of_int num_games in
    
    Printf.printf "\n  Depth %d:\n" depth;
    Printf.printf "    Time: %.3fs for %d games\n" elapsed num_games;
    Printf.printf "    Speed: %.1f games/sec\n" (float_of_int num_games /. elapsed);
    Printf.printf "    Avg score: %.0f\n" avg_score;
    Printf.printf "    Avg moves: %.0f\n" avg_moves
  ) [1; 2]

let benchmark_gp_evolution () =
  Printf.printf "\n5. GP EVOLUTION BENCHMARK\n";
  Printf.printf "==================================================\n";
  
  Printf.printf "  (Skipped - would require full GP engine setup)\n"

let main () =
  (* Initialize tables *)
  init_tables ();
  
  (* Run benchmarks *)
  benchmark_board_operations 10000;
  benchmark_gp_tree_evaluation 1000;
  benchmark_expectimax 10;
  benchmark_full_game 10;
  benchmark_gp_evolution ()

let () = main ()