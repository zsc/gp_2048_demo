open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned
open Gp_2048_lib.Gp_engine

(* Leaderboard entry *)
type leaderboard_entry = {
  program: program;
  generation: int;
  timestamp: float;
  test_scores: int list;
  test_max_tiles: int list;
  avg_score: float;
  avg_max_tile: float;
  max_score: int;
  best_tile: int;
  description: string;
}

(* Global leaderboard *)
let leaderboard = ref []
let leaderboard_file = "leaderboard.txt"

(* Save leaderboard to file *)
let save_leaderboard () =
  let oc = open_out leaderboard_file in
  Printf.fprintf oc "2048 GP Evolution Leaderboard\n";
  Printf.fprintf oc "============================\n\n";
  
  List.iteri (fun i entry ->
    Printf.fprintf oc "Rank %d - Generation %d (%.0f avg score)\n" 
      (i + 1) entry.generation entry.avg_score;
    Printf.fprintf oc "  Description: %s\n" entry.description;
    Printf.fprintf oc "  Average score: %.0f\n" entry.avg_score;
    Printf.fprintf oc "  Max score: %d\n" entry.max_score;
    Printf.fprintf oc "  Average max tile: 2^%.1f\n" entry.avg_max_tile;
    Printf.fprintf oc "  Best tile achieved: 2^%d\n" entry.best_tile;
    Printf.fprintf oc "  Program size: %d nodes\n" (Array.length entry.program.nodes);
    let tm = Unix.localtime entry.timestamp in
    Printf.fprintf oc "  Time: %04d-%02d-%02d %02d:%02d:%02d\n\n" 
      (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
      tm.tm_hour tm.tm_min tm.tm_sec
  ) !leaderboard;
  
  close_out oc;
  Printf.printf "Leaderboard saved to %s\n" leaderboard_file;
  flush stdout

(* Add to leaderboard if good enough *)
let update_leaderboard entry =
  leaderboard := entry :: !leaderboard;
  leaderboard := List.sort (fun a b -> compare b.avg_score a.avg_score) !leaderboard;
  
  (* Keep top 20 *)
  if List.length !leaderboard > 20 then
    leaderboard := List.filteri (fun i _ -> i < 20) !leaderboard;
  
  (* Check rank *)
  let rank = 
    let rec find_index i = function
      | [] -> List.length !leaderboard
      | h::t -> if h == entry then i + 1 else find_index (i + 1) t
    in
    find_index 0 !leaderboard in
  if rank <= 10 then begin
    Printf.printf "\n*** NEW LEADERBOARD ENTRY! Rank #%d ***\n" rank;
    Printf.printf "  Average score: %.0f\n" entry.avg_score;
    Printf.printf "  Best tile: 2^%d\n" entry.best_tile;
    flush stdout
  end;
  
  save_leaderboard ()

(* Thoroughly test a program *)
let test_program program generation description num_games depth =
  Printf.printf "\nTesting program: %s\n" description;
  flush stdout;
  
  let rng = Random.State.make [|int_of_float (Unix.gettimeofday ())|] in
  let scores = ref [] in
  let max_tiles = ref [] in
  
  for i = 1 to num_games do
    let score, max_tile = play_game program rng depth 1000 in
    scores := score :: !scores;
    max_tiles := max_tile :: !max_tiles;
    
    if i mod 5 = 0 then begin
      Printf.printf "  Test game %d/%d: score=%d, tile=2^%d\n" 
        i num_games score max_tile;
      flush stdout
    end
  done;
  
  let avg_score = (List.fold_left (+.) 0. (List.map float_of_int !scores)) /. float_of_int num_games in
  let avg_max_tile = (List.fold_left (+.) 0. (List.map float_of_int !max_tiles)) /. float_of_int num_games in
  let max_score = List.fold_left max 0 !scores in
  let best_tile = List.fold_left max 0 !max_tiles in
  
  {
    program = program;
    generation = generation;
    timestamp = Unix.gettimeofday ();
    test_scores = !scores;
    test_max_tiles = !max_tiles;
    avg_score = avg_score;
    avg_max_tile = avg_max_tile;
    max_score = max_score;
    best_tile = best_tile;
    description = description;
  }

(* Advanced evolution with multiple strategies *)
let evolve_advanced () =
  Printf.printf "Starting Advanced GP Evolution with Leaderboard\n";
  Printf.printf "==============================================\n\n";
  flush stdout;
  
  (* Configuration *)
  let config = {
    pop_size = 50;
    max_depth = 8;
    elite_size = 5;
    tournament_size = 7;
    mutation_rate = 0.15;
    num_generations = 20;
    num_games = 10;
    search_depth = 2;
    max_moves = 500;
  } in
  
  let rng = Random.State.make [|42|] in
  
  (* Initialize with diverse population *)
  Printf.printf "Creating diverse initial population...\n";
  flush stdout;
  
  let population = ref [||] in
  
  (* Add some hand-crafted programs *)
  let hand_crafted = [
    ("Simple", [| Add; NumEmptyCells; MaxTileValue |]);
    ("Weighted", [| Add; Mul; Constant 2.0; NumEmptyCells; MaxTileValue |]);
    ("Smoothness", [| Add; Add; NumEmptyCells; MaxTileValue; SmoothnessScore |]);
    ("Monotonic", [| Add; MonotonicityScore; Mul; Constant 1.5; MaxTileValue |]);
    ("Complex", [| Add; Add; Mul; Constant 2.0; NumEmptyCells; MaxTileValue; 
                   Sub; SmoothnessScore; MonotonicityScore |]);
  ] in
  
  (* Create initial population *)
  let initial_programs = Array.init config.pop_size (fun i ->
    if i < List.length hand_crafted then
      let _, nodes = List.nth hand_crafted i in
      { nodes = nodes; fitness = 0.0; games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 }
    else
      create_random_program rng config.max_depth
  ) in
  
  population := initial_programs;
  
  (* Evolution loop *)
  for gen = 1 to config.num_generations do
    Printf.printf "\n=== Generation %d/%d ===\n" gen config.num_generations;
    flush stdout;
    
    (* Evaluate population *)
    Printf.printf "Evaluating %d individuals...\n" (Array.length !population);
    flush stdout;
    
    let eval_start = Unix.gettimeofday () in
    Array.iteri (fun i prog ->
      let _ = evaluate_fitness prog rng config.num_games config.search_depth config.max_moves in
      if (i + 1) mod 10 = 0 then begin
        Printf.printf "  Evaluated %d/%d\n" (i + 1) (Array.length !population);
        flush stdout
      end
    ) !population;
    
    let eval_time = Unix.gettimeofday () -. eval_start in
    Printf.printf "Evaluation completed in %.1fs\n" eval_time;
    
    (* Sort by fitness *)
    Array.sort (fun a b -> compare b.fitness a.fitness) !population;
    
    (* Display top 5 *)
    Printf.printf "\nTop 5 individuals:\n";
    for i = 0 to min 4 (Array.length !population - 1) do
      let p = !population.(i) in
      Printf.printf "  %d. Fitness: %.1f (avg_score=%.0f, avg_tile=%.1f, nodes=%d)\n" 
        (i + 1) p.fitness p.avg_score p.avg_max_tile (Array.length p.nodes)
    done;
    flush stdout;
    
    (* Test promising candidates *)
    if gen mod 5 = 0 || gen = config.num_generations then begin
      let best = !population.(0) in
      if best.avg_score > 5000.0 then begin
        let desc = Printf.sprintf "Gen %d Elite (fitness=%.1f)" gen best.fitness in
        let entry = test_program best gen desc 20 2 in
        update_leaderboard entry
      end
    end;
    
    (* Show diversity metrics *)
    let unique_structures = 
      Array.fold_left (fun acc p ->
        let size = Array.length p.nodes in
        if List.mem size acc then acc else size :: acc
      ) [] !population 
    in
    Printf.printf "\nPopulation diversity: %d unique program sizes\n" 
      (List.length unique_structures);
    
    (* Evolve if not last generation *)
    if gen < config.num_generations then begin
      Printf.printf "\nEvolving next generation...\n";
      flush stdout;
      
      (* Advanced evolution with multiple strategies *)
      let new_pop = Array.make config.pop_size !population.(0) in
      
      (* Keep elite *)
      for i = 0 to config.elite_size - 1 do
        new_pop.(i) <- !population.(i)
      done;
      
      (* Fill rest with offspring *)
      let idx = ref config.elite_size in
      while !idx < config.pop_size do
        let strategy = Random.State.int rng 100 in
        
        if strategy < 70 then begin
          (* Standard crossover *)
          let p1 = tournament_selection rng !population config.tournament_size in
          let p2 = tournament_selection rng !population config.tournament_size in
          let child1, child2 = crossover rng p1 p2 in
          let child = if Random.State.bool rng then child1 else child2 in
          new_pop.(!idx) <- child;
          incr idx
        end else if strategy < 85 then begin
          (* Mutation only *)
          let parent = tournament_selection rng !population config.tournament_size in
          let child = mutate rng parent config.mutation_rate config.max_depth in
          new_pop.(!idx) <- child;
          incr idx
        end else begin
          (* Fresh random individual *)
          new_pop.(!idx) <- create_random_program rng config.max_depth;
          incr idx
        end
      done;
      
      population := new_pop;
      Printf.printf "Evolution completed\n";
      flush stdout
    end
  done;
  
  (* Final championship *)
  Printf.printf "\n=== FINAL CHAMPIONSHIP ===\n";
  Printf.printf "Testing top 3 programs with 50 games each...\n\n";
  flush stdout;
  
  for i = 0 to min 2 (Array.length !population - 1) do
    let p = !population.(i) in
    let desc = Printf.sprintf "Final Champion #%d" (i + 1) in
    let entry = test_program p config.num_generations desc 50 2 in
    update_leaderboard entry;
    
    Printf.printf "\nChampion #%d final stats:\n" (i + 1);
    Printf.printf "  Average score: %.0f\n" entry.avg_score;
    Printf.printf "  Max score: %d\n" entry.max_score;
    Printf.printf "  Best tile: 2^%d\n" entry.best_tile;
    Printf.printf "  Program complexity: %d nodes\n" (Array.length p.nodes);
    flush stdout
  done;
  
  Printf.printf "\n=== EVOLUTION COMPLETE ===\n";
  Printf.printf "Check %s for full leaderboard\n" leaderboard_file;
  flush stdout

(* Main *)
let () =
  init_tables ();
  evolve_advanced ()