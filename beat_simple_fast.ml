open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Gp_tree_json
open Gp_2048_lib.Gp_engine
open Domainslib

let create_smart_initial_population rng size =
  (* Load simple_fast as the baseline *)
  let simple_fast = 
    try
      load_program_from_json "python/models/simple_fast.json"
    with _ ->
      { nodes = [| Add; NumEmptyCells; MaxTileValue |]; 
        fitness = 0.0; games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 }
  in
  
  let base_strategies = [
    simple_fast.nodes;  (* Include simple_fast as first strategy *)
    [| Add; NumEmptyCells; MaxTileValue |];
    [| Add; MaxTileValue; NumEmptyCells |];
    [| Add; Mul; NumEmptyCells; Constant 2.0; MaxTileValue |];
    [| Add; Mul; MaxTileValue; Constant 1.5; NumEmptyCells |];
    [| Add; Mul; NumEmptyCells; Constant 3.0; MaxTileValue |];
    [| Add; Mul; NumEmptyCells; Constant 4.0; MaxTileValue |];
    [| Add; NumEmptyCells; Mul; MaxTileValue; Constant 2.0 |];
    [| Add; NumEmptyCells; Mul; MaxTileValue; MaxTileValue |];
    [| Add; SafeDiv; NumEmptyCells; Constant 0.1; MaxTileValue |];
    [| Mul; MaxTileValue; SafeDiv; NumEmptyCells; Constant 16.0 |];
    [| IfLTE; NumEmptyCells; Constant 4.0; MaxTileValue; Mul; NumEmptyCells; Constant 5.0 |];
    [| IfLTE; NumEmptyCells; Constant 8.0; Add; NumEmptyCells; MaxTileValue; MaxTileValue |];
    (* Variations of simple_fast *)
    [| Add; Mul; NumEmptyCells; Constant 2.0; MaxTileValue |];
    [| Add; NumEmptyCells; Mul; MaxTileValue; Constant 2.0 |];
    [| Mul; Add; NumEmptyCells; MaxTileValue; Constant 2.0 |];
  ] in
  
  Array.init size (fun i ->
    if i < List.length base_strategies then
      { nodes = List.nth base_strategies i; 
        fitness = 0.0; 
        games_played = 0; 
        avg_score = 0.0; 
        avg_max_tile = 0.0 }
    else
      let base = List.nth base_strategies (i mod List.length base_strategies) in
      let prog = { nodes = base; fitness = 0.0; games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 } in
      let mutated = mutate rng prog 0.3 5 in
      { nodes = mutated.nodes;
        fitness = 0.0;
        games_played = 0;
        avg_score = 0.0;
        avg_max_tile = 0.0 }
  )

let evaluate_quick program rng num_games =
  let scores = ref [] in
  let tiles = ref [] in
  
  for i = 0 to num_games - 1 do
    let game_rng = Random.State.make [|Random.State.int rng 1000000 + i|] in
    let score, max_tile = Gp_2048_lib.Expectimax_aligned.play_game program game_rng 2 1000000 in
    scores := score :: !scores;
    tiles := max_tile :: !tiles
  done;
  
  let avg_score = float_of_int (List.fold_left (+) 0 !scores) /. float_of_int num_games in
  let avg_max_tile = float_of_int (List.fold_left (+) 0 !tiles) /. float_of_int num_games in
  program.avg_score <- avg_score;
  program.avg_max_tile <- avg_max_tile;
  avg_score +. (avg_max_tile ** 2.0)

let evolve_to_beat target_score =
  Printf.printf "=== Evolution to Beat simple_fast (%.0f) ===\n" target_score;
  Printf.printf "Using smart initial population and focused selection\n";
  Printf.printf "Using 6 CPU cores for parallel evaluation\n\n";
  flush stdout;
  
  let pool = Task.setup_pool ~num_domains:6 () in
  let rng = Random.State.make [|int_of_float (Unix.time ())|] in
  
  let config = {
    pop_size = 60;
    max_depth = 6;
    elite_size = 10;
    tournament_size = 7;
    mutation_rate = 0.25;
    num_generations = 30;
    num_games = 10;  (* Increased from 3 to 10 for better evaluation *)
    search_depth = 2;
    max_moves = 1000000;  (* Play until game over - 100x increase *)
  } in
  
  let population = create_smart_initial_population rng config.pop_size in
  let best_ever = ref None in
  
  for gen = 1 to config.num_generations do
    Printf.printf "\nGeneration %d/%d at %s\n" gen config.num_generations 
      (Unix.gettimeofday () |> Unix.gmtime |> fun tm ->
        Printf.sprintf "%02d:%02d:%02d" tm.tm_hour tm.tm_min tm.tm_sec);
    flush stdout;
    
    let eval_start = Unix.gettimeofday () in
    
    (* Parallel evaluation with progress *)
    let completed = ref 0 in
    Task.run pool (fun () ->
      Task.parallel_for pool ~start:0 ~finish:(config.pop_size - 1)
        ~body:(fun i ->
          let prog = population.(i) in
          (* Create independent RNG for each thread *)
          let thread_rng = Random.State.make [|gen * 1000 + i|] in
          let fitness = evaluate_quick prog thread_rng config.num_games in
          prog.fitness <- fitness;
          (* avg_score and avg_max_tile are already set by evaluate_quick *)
          
          (* Progress reporting *)
          let c = incr completed; !completed in
          if c mod 10 = 0 then begin
            Printf.printf "  Evaluated %d/%d (%.1f%%)\r" c config.pop_size 
              (float_of_int c /. float_of_int config.pop_size *. 100.0);
            flush stdout
          end
        )
    );
    
    let eval_time = Unix.gettimeofday () -. eval_start in
    Printf.printf "\n  Evaluation complete in %.1fs (%.1f ind/sec)\n" 
      eval_time (float_of_int config.pop_size /. eval_time);
    
    Array.sort (fun a b -> compare b.fitness a.fitness) population;
    
    Printf.printf "\n  Best fitness: %.0f (est. score: %.0f)\n" 
      population.(0).fitness population.(0).avg_score;
    
    (match !best_ever with
     | None -> best_ever := Some population.(0)
     | Some prev -> 
         if population.(0).fitness > prev.fitness then
           best_ever := Some population.(0));
    
    (* Save checkpoint every 5 generations *)
    if gen mod 5 = 0 then begin
      let checkpoint_file = Printf.sprintf "python/models/checkpoint_gen%d.json" gen in
      let best = population.(0) in
      let oc = open_out checkpoint_file in
      Printf.fprintf oc "{\n";
      Printf.fprintf oc "  \"nodes\": [%s],\n" 
        (best.nodes |> Array.to_list |> List.map node_to_string |> 
         List.map (fun s -> "\"" ^ s ^ "\"") |> String.concat ", ");
      Printf.fprintf oc "  \"node_budget_max\": 500,\n";
      Printf.fprintf oc "  \"generation\": %d,\n" gen;
      Printf.fprintf oc "  \"fitness\": %.2f,\n" best.fitness;
      Printf.fprintf oc "  \"avg_score_estimate\": %.2f\n" best.avg_score;
      Printf.fprintf oc "}\n";
      close_out oc;
      Printf.printf "  💾 Saved checkpoint to %s\n" checkpoint_file;
      flush stdout
    end;
    
    if gen mod 5 = 0 || gen = config.num_generations then begin
      Printf.printf "  Thorough evaluation of best candidate...\n";
      flush stdout;
      
      let best = population.(0) in
      let test_scores = ref [] in
      let test_tiles = ref [] in
      
      let results = Task.run pool (fun () ->
        Task.parallel_for_reduce pool 
          ~start:0 
          ~finish:19
          ~body:(fun i ->
            let game_rng = Random.State.make [|42 + i * 13|] in
            let score, max_tile = Gp_2048_lib.Expectimax_aligned.play_game best game_rng 2 1000000 in
            [(score, max_tile)]
          )
          (fun acc lst -> acc @ lst)
          []
      ) in
      
      List.iter (fun (score, tile) ->
        test_scores := score :: !test_scores;
        test_tiles := tile :: !test_tiles
      ) results;
      
      let avg_score = float_of_int (List.fold_left (+) 0 !test_scores) /. 20.0 in
      let max_score = List.fold_left max 0 !test_scores in
      let avg_tile = float_of_int (List.fold_left (+) 0 !test_tiles) /. 20.0 in
      
      Printf.printf "  20-game test results:\n";
      Printf.printf "    Average score: %.0f %s\n" avg_score
        (if avg_score > target_score then "✅" else "❌");
      Printf.printf "    Max score: %d\n" max_score;
      Printf.printf "    Average max tile: %.0f (2^%.1f)\n" avg_tile (log avg_tile /. log 2.0);
      Printf.printf "    Program: %s\n" (program_to_string best);
      flush stdout;
      
      if avg_score > target_score then begin
        Printf.printf "  🎉 BEAT THE TARGET! Saving model...\n";
        
        let filename = Printf.sprintf "python/models/champion_gen%d.json" gen in
        let oc = open_out filename in
        Printf.fprintf oc "{\n";
        Printf.fprintf oc "  \"nodes\": [%s],\n" 
          (best.nodes |> Array.to_list |> List.map node_to_string |> 
           List.map (fun s -> "\"" ^ s ^ "\"") |> String.concat ", ");
        Printf.fprintf oc "  \"node_budget_max\": 500,\n";
        Printf.fprintf oc "  \"description\": \"Evolution champion - beat simple_fast!\",\n";
        Printf.fprintf oc "  \"generation\": %d,\n" gen;
        Printf.fprintf oc "  \"avg_score\": %.2f,\n" avg_score;
        Printf.fprintf oc "  \"max_score\": %d,\n" max_score;
        Printf.fprintf oc "  \"avg_max_tile\": %.2f,\n" avg_tile;
        Printf.fprintf oc "  \"fitness\": %.2f\n" (avg_score +. (avg_tile ** 2.0));
        Printf.fprintf oc "}\n";
        close_out oc;
        
        Printf.printf "  Model saved to %s\n" filename;
      end
    end;
    
    if gen < config.num_generations then begin
      let new_pop = Array.make config.pop_size population.(0) in
      
      for i = 0 to config.elite_size - 1 do
        new_pop.(i) <- population.(i)
      done;
      
      for i = config.elite_size to config.pop_size - 1 do
        let parent1 = tournament_selection rng population config.tournament_size in
        let parent2 = tournament_selection rng population config.tournament_size in
        
        let child = 
          if Random.State.float rng 1.0 < 0.8 then
            let child1, _ = crossover rng parent1 parent2 in
            child1
          else
            parent1
        in
        
        let mutated = 
          if Random.State.float rng 1.0 < config.mutation_rate then
            mutate rng child config.mutation_rate config.max_depth
          else
            child
        in
        
        new_pop.(i) <- mutated
      done;
      
      Array.blit new_pop 0 population 0 config.pop_size
    end
  done;
  
  match !best_ever with
  | None -> Printf.printf "No solution found\n"
  | Some best ->
      Printf.printf "\n=== FINAL EVALUATION ===\n";
      Printf.printf "Best program: %s\n" (program_to_string best);
      
      let final_scores = ref [] in
      let final_tiles = ref [] in
      
      Printf.printf "Running 50 game final test...\n";
      for i = 0 to 49 do
        let game_rng = Random.State.make [|100 + i * 7|] in
        let score, max_tile = Gp_2048_lib.Expectimax_aligned.play_game best game_rng 2 1000000 in
        final_scores := score :: !final_scores;
        final_tiles := max_tile :: !final_tiles;
        if (i + 1) mod 10 = 0 then Printf.printf "  %d/50\n" (i + 1)
      done;
      
      let final_avg = float_of_int (List.fold_left (+) 0 !final_scores) /. 50.0 in
      let final_max = List.fold_left max 0 !final_scores in
      let final_tile_avg = float_of_int (List.fold_left (+) 0 !final_tiles) /. 50.0 in
      
      Printf.printf "\nFINAL RESULTS (50 games):\n";
      Printf.printf "  Average score: %.0f\n" final_avg;
      Printf.printf "  Max score: %d\n" final_max;
      Printf.printf "  Average max tile: %.0f\n" final_tile_avg;
      
      if final_avg > target_score then
        Printf.printf "\n🏆 SUCCESS! Beat simple_fast by %.0f points!\n" (final_avg -. target_score)
      else
        Printf.printf "\n❌ Fell short by %.0f points. Try again!\n" (target_score -. final_avg);
  
  Task.teardown_pool pool

let () =
  init_tables ();
  evolve_to_beat 7356.0