open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned
open Gp_2048_lib.Gp_engine

let time_it name f =
  let start = Unix.gettimeofday () in
  let result = f () in
  let elapsed = Unix.gettimeofday () -. start in
  Printf.printf "%s took %.3fs\n" name elapsed;
  flush stdout;
  (result, elapsed)

(* Experiment 1: Compare different search depths *)
let experiment_depth_comparison num_games =
  Printf.printf "\n=== EXPERIMENT 1: Search Depth Comparison ===\n";
  Printf.printf "Running %d games per depth...\n\n" num_games;
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  let rng = Random.State.make [|42|] in
  
  List.iter (fun depth ->
    Printf.printf "Depth %d:\n" depth;
    flush stdout;
    
    let scores = ref [] in
    let max_tiles = ref [] in
    
    let _, elapsed = time_it (Printf.sprintf "  Playing %d games" num_games) (fun () ->
      for game = 1 to num_games do
        let score, max_tile = play_game simple_program rng depth 1000 in
        scores := score :: !scores;
        max_tiles := max_tile :: !max_tiles;
        
        (* Progress indicator *)
        if game mod 10 = 0 then begin
          Printf.printf "    Game %d/%d completed\n" game num_games;
          flush stdout
        end
      done
    ) in
    
    let avg_score = (List.fold_left (+) 0 !scores) / num_games in
    let avg_max_tile = (List.fold_left (+) 0 !max_tiles) / num_games in
    let max_score = List.fold_left max 0 !scores in
    let max_tile_achieved = List.fold_left max 0 !max_tiles in
    
    Printf.printf "  Results:\n";
    Printf.printf "    Avg score: %d\n" avg_score;
    Printf.printf "    Max score: %d\n" max_score;
    Printf.printf "    Avg max tile: %d (2^%d)\n" (1 lsl avg_max_tile) avg_max_tile;
    Printf.printf "    Best tile: %d (2^%d)\n" (1 lsl max_tile_achieved) max_tile_achieved;
    Printf.printf "    Time: %.3fs (%.1f games/sec)\n\n" elapsed (float_of_int num_games /. elapsed);
    flush stdout
  ) [1; 2; 3; 4]

(* Experiment 2: Evaluate different GP programs *)
let experiment_gp_programs num_games =
  Printf.printf "\n=== EXPERIMENT 2: GP Program Comparison ===\n";
  Printf.printf "Comparing different evaluation functions (%d games each)...\n\n" num_games;
  flush stdout;
  
  let rng = Random.State.make [|42|] in
  
  (* Different evaluation programs *)
  let programs = [
    ("Simple (Empty + MaxTile)", 
     [| Add; NumEmptyCells; MaxTileValue |]);
    
    ("Weighted (2*Empty + MaxTile)", 
     [| Add; Mul; Constant 2.0; NumEmptyCells; MaxTileValue |]);
    
    ("Complex (Empty + MaxTile + Smoothness)", 
     [| Add; Add; NumEmptyCells; MaxTileValue; SmoothnessScore |]);
    
    ("Monotonicity focused", 
     [| Add; MonotonicityScore; MaxTileValue |]);
  ] in
  
  List.iter (fun (name, nodes) ->
    Printf.printf "Program: %s\n" name;
    flush stdout;
    
    let program = {
      nodes = nodes;
      fitness = 0.0;
      games_played = 0;
      avg_score = 0.0;
      avg_max_tile = 0.0;
    } in
    
    let scores = ref [] in
    let max_tiles = ref [] in
    
    let _, elapsed = time_it (Printf.sprintf "  Playing %d games" num_games) (fun () ->
      for game = 1 to num_games do
        let score, max_tile = play_game program rng 2 1000 in
        scores := score :: !scores;
        max_tiles := max_tile :: !max_tiles;
        
        if game mod 5 = 0 then begin
          Printf.printf "    Game %d/%d: score=%d, max_tile=2^%d\n" 
            game num_games score max_tile;
          flush stdout
        end
      done
    ) in
    
    let avg_score = (List.fold_left (+) 0 !scores) / num_games in
    let avg_max_tile = (List.fold_left (+) 0 !max_tiles) / num_games in
    
    Printf.printf "  Results:\n";
    Printf.printf "    Avg score: %d\n" avg_score;
    Printf.printf "    Avg max tile: 2^%d\n" avg_max_tile;
    Printf.printf "    Games/sec: %.1f\n\n" (float_of_int num_games /. elapsed);
    flush stdout
  ) programs

(* Experiment 3: Evolve and test GP programs *)
let experiment_evolution generations pop_size =
  Printf.printf "\n=== EXPERIMENT 3: GP Evolution ===\n";
  Printf.printf "Evolving population of %d for %d generations...\n\n" pop_size generations;
  flush stdout;
  
  let config = {
    pop_size = pop_size;
    max_depth = 7;
    elite_size = 2;
    tournament_size = 5;
    mutation_rate = 0.1;
    num_generations = generations;
    num_games = 5;
    search_depth = 1;
    max_moves = 200;
  } in
  
  let rng = Random.State.make [|42|] in
  let population = ref (create_initial_population rng config.pop_size config.max_depth) in
  
  for gen = 1 to generations do
    Printf.printf "Generation %d/%d:\n" gen generations;
    flush stdout;
    
    (* Evaluate population *)
    let _, eval_time = time_it "  Evaluating fitness" (fun () ->
      Array.iter (fun prog ->
        let _ = evaluate_fitness prog rng config.num_games config.search_depth config.max_moves in
        ()
      ) !population
    ) in
    
    (* Sort by fitness *)
    Array.sort (fun a b -> compare b.fitness a.fitness) !population;
    
    let best = !population.(0) in
    let worst = !population.(Array.length !population - 1) in
    
    Printf.printf "  Best fitness: %.1f (avg_score=%.0f, avg_tile=%.1f)\n" 
      best.fitness best.avg_score best.avg_max_tile;
    Printf.printf "  Worst fitness: %.1f\n" worst.fitness;
    Printf.printf "  Evaluation time: %.1fs\n" eval_time;
    
    (* Show best program structure *)
    if gen = 1 || gen mod 5 = 0 || gen = generations then begin
      Printf.printf "  Best program has %d nodes\n" (Array.length best.nodes);
      flush stdout
    end;
    
    (* Evolve if not last generation *)
    if gen < generations then begin
      let _, evolve_time = time_it "  Evolving" (fun () ->
        population := evolve_population rng !population config.elite_size config.tournament_size config.mutation_rate config.max_depth
      ) in
      Printf.printf "  Evolution time: %.1fs\n\n" evolve_time;
      flush stdout
    end
  done;
  
  (* Test best program more thoroughly *)
  Printf.printf "\nTesting best evolved program with 20 games at depth 2...\n";
  flush stdout;
  
  let best = !population.(0) in
  let test_scores = ref [] in
  let test_tiles = ref [] in
  
  for i = 1 to 20 do
    let score, max_tile = play_game best rng 2 1000 in
    test_scores := score :: !test_scores;
    test_tiles := max_tile :: !test_tiles;
    Printf.printf "  Game %d: score=%d, max_tile=2^%d\n" i score max_tile;
    flush stdout
  done;
  
  let avg_test_score = (List.fold_left (+) 0 !test_scores) / 20 in
  let avg_test_tile = (List.fold_left (+) 0 !test_tiles) / 20 in
  
  Printf.printf "\nFinal test results:\n";
  Printf.printf "  Avg score: %d\n" avg_test_score;
  Printf.printf "  Avg max tile: 2^%d\n" avg_test_tile;
  flush stdout

(* Main experiment runner *)
let main () =
  (* Initialize tables *)
  init_tables ();
  
  Printf.printf "Starting OCaml 2048 Experiments\n";
  Printf.printf "================================\n";
  flush stdout;
  
  (* Run experiments *)
  experiment_depth_comparison 50;
  experiment_gp_programs 30;
  experiment_evolution 10 30;
  
  Printf.printf "\nAll experiments completed!\n";
  flush stdout

let () = main ()