(* Simple training script to generate various models *)
open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Gp_tree_json
open Gp_2048_lib.Gp_engine

(* Training configuration *)
type train_config = {
  name: string;
  generations: int;
  pop_size: int;
  node_budget: int;
  games_per_eval: int;
  description: string;
}

(* Train and save a model *)
let train_model config =
  Printf.printf "\n=== Training %s ===\n" config.name;
  Printf.printf "Description: %s\n" config.description;
  Printf.printf "Generations: %d, Population: %d\n" config.generations config.pop_size;
  flush stdout;
  
  (* Create GP config *)
  let gp_config = {
    pop_size = config.pop_size;
    max_depth = 6;
    elite_size = 5;
    tournament_size = 5;
    mutation_rate = 0.2;
    num_generations = config.generations;
    num_games = config.games_per_eval;
    search_depth = 2;
    max_moves = 500;
  } in
  
  (* Run evolution *)
  let start_time = Unix.gettimeofday () in
  let rng = Random.State.make [|42|] in
  let best_program = run_evolution rng gp_config in
  let train_time = Unix.gettimeofday () -. start_time in
  
  Printf.printf "Training completed in %.1f seconds\n" train_time;
  
  (* Evaluate final model *)
  Printf.printf "Evaluating final model (20 games)...\n";
  let scores = ref [] in
  let tiles = ref [] in
  
  for i = 0 to 19 do
    let rng = Random.State.make [|1000 + i|] in
    let score, max_tile = Gp_2048_lib.Expectimax_aligned.play_game best_program rng 2 500 in
    scores := score :: !scores;
    tiles := max_tile :: !tiles
  done;
  
  let avg_score = float_of_int (List.fold_left (+) 0 !scores) /. 20.0 in
  let max_score = List.fold_left max 0 !scores in
  let avg_tile = float_of_int (List.fold_left (+) 0 !tiles) /. 20.0 in
  let max_tile = List.fold_left max 0 !tiles in
  
  Printf.printf "Results:\n";
  Printf.printf "  Average score: %.0f\n" avg_score;
  Printf.printf "  Max score: %d\n" max_score;
  Printf.printf "  Average max tile: %.0f\n" avg_tile;
  Printf.printf "  Best tile: %d\n" max_tile;
  
  (* Save model *)
  let filename = Printf.sprintf "python/models/%s.json" config.name in
  
  (* Convert program to JSON array *)
  let nodes_array = best_program.nodes
    |> Array.to_list
    |> List.map node_to_string
    |> List.map (fun s -> "\"" ^ s ^ "\"")
    |> String.concat ", "
  in
  
  (* Write JSON directly *)
  let oc = open_out filename in
  Printf.fprintf oc "{\n";
  Printf.fprintf oc "  \"nodes\": [%s],\n" nodes_array;
  Printf.fprintf oc "  \"node_budget_max\": %d,\n" config.node_budget;
  Printf.fprintf oc "  \"description\": \"%s\",\n" config.description;
  Printf.fprintf oc "  \"avg_score\": %.2f,\n" avg_score;
  Printf.fprintf oc "  \"max_score\": %d,\n" max_score;
  Printf.fprintf oc "  \"avg_max_tile\": %.2f,\n" avg_tile;
  Printf.fprintf oc "  \"best_tile\": %d,\n" max_tile;
  Printf.fprintf oc "  \"train_time\": %.1f,\n" train_time;
  Printf.fprintf oc "  \"fitness\": %.2f\n" (avg_score +. (avg_tile ** 2.0));
  Printf.fprintf oc "}\n";
  close_out oc;
  
  Printf.printf "Model saved to %s\n" filename;
  (config.name, avg_score, max_score, avg_tile, max_tile)

let () =
  init_tables ();
  
  (* Ensure models directory exists *)
  let models_dir = "python/models" in
  if not (Sys.file_exists models_dir) then
    Unix.mkdir models_dir 0o755;
  
  (* Define training configurations *)
  let configs = [
    { name = "ultra_fast_v3"; 
      generations = 20; pop_size = 60; node_budget = 500;
      games_per_eval = 5;
      description = "Ultra-fast play for real-time applications (500 nodes)" };
    
    { name = "balanced_pro"; 
      generations = 30; pop_size = 50; node_budget = 1000;
      games_per_eval = 5;
      description = "Professional balanced play (1000 nodes)" };
    
    { name = "deep_master"; 
      generations = 25; pop_size = 40; node_budget = 5000;
      games_per_eval = 3;
      description = "Deep analysis master (5000 nodes)" };
    
    { name = "tournament_champion"; 
      generations = 35; pop_size = 30; node_budget = 10000;
      games_per_eval = 3;
      description = "Tournament-level deep search (10000 nodes)" };
  ] in
  
  (* Train all models *)
  Printf.printf "Starting training of %d models...\n" (List.length configs);
  let results = List.map train_model configs in
  
  (* Print final leaderboard *)
  Printf.printf "\n\n=== TRAINING COMPLETE - FINAL LEADERBOARD ===\n";
  Printf.printf "%-20s %10s %10s %10s %10s\n" 
    "Model" "Avg Score" "Max Score" "Avg Tile" "Best Tile";
  Printf.printf "%s\n" (String.make 70 '-');
  
  let sorted_results = List.sort (fun (_, a1, _, _, _) (_, a2, _, _, _) -> 
    compare a2 a1
  ) results in
  
  List.iter (fun (name, avg_score, max_score, avg_tile, max_tile) ->
    Printf.printf "%-20s %10.0f %10d %10.0f %10d\n"
      name avg_score max_score avg_tile max_tile
  ) sorted_results;
  
  Printf.printf "\nAll models saved to python/models/\n"