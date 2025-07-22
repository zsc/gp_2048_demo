open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax_aligned
open Gp_2048_lib.Gp_engine

let results_file = "experiment_results.txt"

let append_result str =
  let oc = open_out_gen [Open_append; Open_creat] 0o644 results_file in
  output_string oc str;
  output_char oc '\n';
  close_out oc

let time_it name f =
  let start = Unix.gettimeofday () in
  let result = f () in
  let elapsed = Unix.gettimeofday () -. start in
  let msg = Printf.sprintf "%s took %.3fs" name elapsed in
  Printf.printf "%s\n" msg;
  append_result msg;
  flush stdout;
  (result, elapsed)

(* Quick depth comparison *)
let experiment_depth_comparison () =
  let msg = "\n=== EXPERIMENT 1: Quick Depth Comparison ===" in
  Printf.printf "%s\n" msg;
  append_result msg;
  flush stdout;
  
  let simple_program = {
    nodes = [| Add; NumEmptyCells; MaxTileValue |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  let rng = Random.State.make [|42|] in
  
  List.iter (fun (depth, num_games) ->
    let msg = Printf.sprintf "\nDepth %d (%d games):" depth num_games in
    Printf.printf "%s\n" msg;
    append_result msg;
    flush stdout;
    
    let scores = ref [] in
    let max_tiles = ref [] in
    
    let _, elapsed = time_it (Printf.sprintf "  Playing %d games" num_games) (fun () ->
      for game = 1 to num_games do
        let score, max_tile = play_game simple_program rng depth 500 in  (* Limit to 500 moves *)
        scores := score :: !scores;
        max_tiles := max_tile :: !max_tiles;
        
        if game mod 5 = 0 then begin
          let msg = Printf.sprintf "    Game %d/%d: score=%d, tile=%d" 
            game num_games score max_tile in
          Printf.printf "%s\n" msg;
          append_result msg;
          flush stdout
        end
      done
    ) in
    
    let avg_score = (List.fold_left (+) 0 !scores) / num_games in
    let avg_max_tile = (List.fold_left (+) 0 !max_tiles) / num_games in
    let games_per_sec = float_of_int num_games /. elapsed in
    
    let results = [
      Printf.sprintf "  Avg score: %d" avg_score;
      Printf.sprintf "  Avg max tile: 2^%d" avg_max_tile;
      Printf.sprintf "  Games/sec: %.1f" games_per_sec;
    ] in
    
    List.iter (fun msg -> Printf.printf "%s\n" msg; append_result msg) results;
    flush stdout
  ) [(1, 20); (2, 10); (3, 5)]  (* Fewer games for higher depths *)

(* Compare GP programs *)
let experiment_gp_programs () =
  let msg = "\n=== EXPERIMENT 2: GP Program Comparison ===" in
  Printf.printf "%s\n" msg;
  append_result msg;
  flush stdout;
  
  let rng = Random.State.make [|42|] in
  
  let programs = [
    ("Simple", [| Add; NumEmptyCells; MaxTileValue |]);
    ("Weighted", [| Add; Mul; Constant 2.0; NumEmptyCells; MaxTileValue |]);
    ("Smoothness", [| Add; Add; NumEmptyCells; MaxTileValue; SmoothnessScore |]);
  ] in
  
  List.iter (fun (name, nodes) ->
    let msg = Printf.sprintf "\nProgram: %s" name in
    Printf.printf "%s\n" msg;
    append_result msg;
    flush stdout;
    
    let program = {
      nodes = nodes;
      fitness = 0.0;
      games_played = 0;
      avg_score = 0.0;
      avg_max_tile = 0.0;
    } in
    
    let scores = ref [] in
    
    let _, elapsed = time_it "  Playing 10 games" (fun () ->
      for game = 1 to 10 do
        let score, max_tile = play_game program rng 2 500 in
        scores := score :: !scores;
        
        if game = 5 || game = 10 then begin
          let msg = Printf.sprintf "    Game %d: score=%d, tile=%d" 
            game score max_tile in
          Printf.printf "%s\n" msg;
          append_result msg;
          flush stdout
        end
      done
    ) in
    
    let avg_score = (List.fold_left (+) 0 !scores) / 10 in
    let msg = Printf.sprintf "  Avg score: %d (%.1f games/sec)" 
      avg_score (10.0 /. elapsed) in
    Printf.printf "%s\n" msg;
    append_result msg;
    flush stdout
  ) programs

(* Quick evolution test *)
let experiment_evolution () =
  let msg = "\n=== EXPERIMENT 3: Quick Evolution Test ===" in
  Printf.printf "%s\n" msg;
  append_result msg;
  flush stdout;
  
  let config = {
    pop_size = 20;
    max_depth = 5;
    elite_size = 2;
    tournament_size = 3;
    mutation_rate = 0.1;
    num_generations = 5;
    num_games = 3;
    search_depth = 1;
    max_moves = 200;
  } in
  
  let rng = Random.State.make [|42|] in
  let population = ref (create_initial_population rng config.pop_size config.max_depth) in
  
  for gen = 1 to config.num_generations do
    let msg = Printf.sprintf "\nGeneration %d/%d:" gen config.num_generations in
    Printf.printf "%s\n" msg;
    append_result msg;
    flush stdout;
    
    (* Evaluate population *)
    Array.iter (fun prog ->
      let _ = evaluate_fitness prog rng config.num_games config.search_depth config.max_moves in
      ()
    ) !population;
    
    (* Sort by fitness *)
    Array.sort (fun a b -> compare b.fitness a.fitness) !population;
    
    let best = !population.(0) in
    let results = [
      Printf.sprintf "  Best fitness: %.1f" best.fitness;
      Printf.sprintf "  Best avg_score: %.0f" best.avg_score;
      Printf.sprintf "  Best avg_tile: 2^%.1f" best.avg_max_tile;
    ] in
    
    List.iter (fun msg -> Printf.printf "%s\n" msg; append_result msg) results;
    flush stdout;
    
    (* Evolve if not last generation *)
    if gen < config.num_generations then
      population := evolve_population rng !population config.elite_size 
        config.tournament_size config.mutation_rate config.max_depth
  done;
  
  (* Final test *)
  let msg = "\nFinal test of best program (5 games):" in
  Printf.printf "%s\n" msg;
  append_result msg;
  
  let best = !population.(0) in
  let final_scores = ref [] in
  
  for i = 1 to 5 do
    let score, max_tile = play_game best rng 2 500 in
    final_scores := score :: !final_scores;
    let msg = Printf.sprintf "  Game %d: score=%d, tile=%d" i score max_tile in
    Printf.printf "%s\n" msg;
    append_result msg;
    flush stdout
  done;
  
  let avg_final = (List.fold_left (+) 0 !final_scores) / 5 in
  let msg = Printf.sprintf "\n  Final avg score: %d" avg_final in
  Printf.printf "%s\n" msg;
  append_result msg

let main () =
  (* Initialize tables *)
  init_tables ();
  
  (* Clear results file *)
  let oc = open_out results_file in
  output_string oc "OCaml 2048 Experiment Results\n";
  output_string oc "============================\n";
  close_out oc;
  
  Printf.printf "Starting OCaml 2048 Quick Experiments\n";
  Printf.printf "Results will be saved to: %s\n" results_file;
  Printf.printf "=====================================\n";
  flush stdout;
  
  (* Run experiments *)
  experiment_depth_comparison ();
  experiment_gp_programs ();
  experiment_evolution ();
  
  let msg = "\nAll experiments completed! Results saved to experiment_results.txt" in
  Printf.printf "%s\n" msg;
  append_result msg;
  flush stdout

let () = main ()