open Gp_2048_lib.Gp_engine
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax

let print_usage () =
  Printf.printf "Usage: gp_2048 [options]\n";
  Printf.printf "Options:\n";
  Printf.printf "  --pop-size <n>       Population size (default: 50)\n";
  Printf.printf "  --generations <n>    Number of generations (default: 50)\n";
  Printf.printf "  --depth <n>          Max tree depth (default: 5)\n";
  Printf.printf "  --games <n>          Games per fitness evaluation (default: 10)\n";
  Printf.printf "  --search-depth <n>   Expectimax search depth (default: 2)\n";
  Printf.printf "  --seed <n>           Random seed (default: current time)\n";
  Printf.printf "  --play               Play a game with the evolved program\n";
  Printf.printf "  --help               Show this help\n"

let rec parse_args args config mode =
  match args with
  | [] -> (config, mode)
  | "--pop-size" :: n :: rest ->
    parse_args rest { config with pop_size = int_of_string n } mode
  | "--generations" :: n :: rest ->
    parse_args rest { config with num_generations = int_of_string n } mode
  | "--depth" :: n :: rest ->
    parse_args rest { config with max_depth = int_of_string n } mode
  | "--games" :: n :: rest ->
    parse_args rest { config with num_games = int_of_string n } mode
  | "--search-depth" :: n :: rest ->
    parse_args rest { config with search_depth = int_of_string n } mode
  | "--seed" :: n :: rest ->
    parse_args rest config (`Train (Some (int_of_string n)))
  | "--play" :: rest ->
    parse_args rest config `Play
  | "--help" :: _ ->
    print_usage ();
    exit 0
  | arg :: _ ->
    Printf.eprintf "Unknown argument: %s\n" arg;
    print_usage ();
    exit 1

let play_interactive program =
  let rng = Random.State.make_self_init () in
  let rec game_loop () =
    Printf.printf "\nStarting new game...\n";
    Printf.printf "Search depth for playing: ";
    flush stdout;
    let search_depth = 
      try read_int ()
      with _ -> 3
    in
    
    let score, max_tile = play_game program rng search_depth 10000 in
    Printf.printf "\nGame Over!\n";
    Printf.printf "Final score: %d\n" score;
    Printf.printf "Max tile: %d\n" max_tile;
    
    Printf.printf "\nPlay again? (y/n): ";
    flush stdout;
    match read_line () with
    | "y" | "Y" -> game_loop ()
    | _ -> ()
  in
  game_loop ()

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let config, mode = parse_args args default_config (`Train None) in
  
  match mode with
  | `Train seed_opt ->
    let rng = match seed_opt with
      | Some seed -> 
        Printf.printf "Using seed: %d\n" seed;
        Random.State.make [|seed|]
      | None -> 
        Random.State.make_self_init ()
    in
    
    Printf.printf "\nStarting evolution with configuration:\n";
    Printf.printf "Population size: %d\n" config.pop_size;
    Printf.printf "Generations: %d\n" config.num_generations;
    Printf.printf "Max tree depth: %d\n" config.max_depth;
    Printf.printf "Games per evaluation: %d\n" config.num_games;
    Printf.printf "Search depth: %d\n" config.search_depth;
    Printf.printf "\n";
    
    let best_program = run_evolution rng config in
    
    Printf.printf "\n=== Evolution Complete ===\n";
    Printf.printf "Best program fitness: %.2f\n" best_program.fitness;
    Printf.printf "Best program avg score: %.2f\n" best_program.avg_score;
    Printf.printf "Best program avg max tile: %.2f\n" best_program.avg_max_tile;
    Printf.printf "\nProgram: %s\n" (program_to_string best_program);
    
    Printf.printf "\nWould you like to play a game with this program? (y/n): ";
    flush stdout;
    (match read_line () with
    | "y" | "Y" -> play_interactive best_program
    | _ -> ())
    
  | `Play ->
    Printf.printf "Play mode requires first training a program.\n";
    Printf.printf "Run without --play to train, then use --play.\n";
    exit 1