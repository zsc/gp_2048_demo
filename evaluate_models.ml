(* Quick evaluation of existing models *)
open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Gp_tree_json
open Gp_2048_lib.Expectimax_aligned

let evaluate_model_file filename num_games =
  try
    let ic = open_in filename in
    let json_string = really_input_string ic (in_channel_length ic) in
    close_in ic;
    
    let program = load_program_from_json json_string in
    
    (* Extract node budget from filename as a workaround *)
    let node_budget = 
      let name = Filename.basename filename in
      if name = "simple_fast.json" then 500
      else if name = "high_performance.json" then 1000  
      else if name = "balanced_best.json" then 5000
      else 1000
    in
    
    Printf.printf "\nEvaluating: %s\n" (Filename.basename filename);
    Printf.printf "Program: %s\n" (program_to_string program);
    Printf.printf "Node budget: %d\n" node_budget;
        Printf.printf "Playing %d games...\n" num_games;
        flush stdout;
        
        let scores = ref [] in
        let tiles = ref [] in
        let start_time = Unix.gettimeofday () in
        
        for i = 0 to num_games - 1 do
          let rng = Random.State.make [|42 + i * 7|] in
          let score, max_tile = play_game program rng 2 500 in
          scores := score :: !scores;
          tiles := max_tile :: !tiles;
          if (i + 1) mod 5 = 0 then begin
            Printf.printf "  Completed %d/%d games\n" (i + 1) num_games;
            flush stdout
          end
        done;
        
        let eval_time = Unix.gettimeofday () -. start_time in
        
        let avg_score = float_of_int (List.fold_left (+) 0 !scores) /. float_of_int num_games in
        let max_score = List.fold_left max 0 !scores in
        let min_score = List.fold_left min max_int !scores in
        let avg_tile = float_of_int (List.fold_left (+) 0 !tiles) /. float_of_int num_games in
        let max_tile = List.fold_left max 0 !tiles in
        
        Printf.printf "Results:\n";
        Printf.printf "  Average score: %.0f\n" avg_score;
        Printf.printf "  Score range: %d - %d\n" min_score max_score;
        Printf.printf "  Average max tile: %.0f (2^%.1f)\n" avg_tile (log avg_tile /. log 2.0);
        Printf.printf "  Best tile achieved: %d\n" max_tile;
        Printf.printf "  Evaluation time: %.1f seconds (%.1f games/sec)\n" 
          eval_time (float_of_int num_games /. eval_time);
        
        (Filename.basename filename, avg_score, max_score, avg_tile, max_tile)
  with
  | Sys_error msg ->
      Printf.printf "Error reading %s: %s\n" filename msg;
      (Filename.basename filename, 0.0, 0, 0.0, 0)

let () =
  init_tables ();
  
  let models = [
    "python/models/simple_fast.json";
    "python/models/balanced_best.json";
    "python/models/high_performance.json";
  ] in
  
  Printf.printf "=== 2048 Model Evaluation ===\n";
  Printf.printf "Evaluating %d models with 50 games each\n\n" (List.length models);
  
  let results = List.map (fun model -> evaluate_model_file model 50) models in
  
  Printf.printf "\n\n=== LEADERBOARD ===\n";
  Printf.printf "%-25s %12s %12s %12s %12s\n" 
    "Model" "Avg Score" "Max Score" "Avg Tile" "Best Tile";
  Printf.printf "%s\n" (String.make 85 '-');
  
  let sorted = List.sort (fun (_, a1, _, _, _) (_, a2, _, _, _) -> 
    compare a2 a1
  ) results in
  
  List.iter (fun (name, avg_score, max_score, avg_tile, max_tile) ->
    Printf.printf "%-25s %12.0f %12d %12.0f %12d\n"
      name avg_score max_score avg_tile max_tile
  ) sorted;
  
  (* Save leaderboard *)
  let oc = open_out "results/model_evaluation.txt" in
  Printf.fprintf oc "2048 Model Evaluation Results\n";
  Printf.fprintf oc "Date: %s\n" (Unix.time () |> Unix.gmtime |> fun tm ->
    Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d UTC"
      (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
      tm.tm_hour tm.tm_min tm.tm_sec);
  Printf.fprintf oc "Games per model: 50\n\n";
  
  Printf.fprintf oc "%-25s %12s %12s %12s %12s\n" 
    "Model" "Avg Score" "Max Score" "Avg Tile" "Best Tile";
  Printf.fprintf oc "%s\n" (String.make 85 '-');
  
  List.iter (fun (name, avg_score, max_score, avg_tile, max_tile) ->
    Printf.fprintf oc "%-25s %12.0f %12d %12.0f %12d\n"
      name avg_score max_score avg_tile max_tile
  ) sorted;
  
  close_out oc;
  Printf.printf "\nResults saved to results/model_evaluation.txt\n"