open Gp_tree
open Expectimax

type population = program array

type config = {
  pop_size: int;
  max_depth: int;
  elite_size: int;
  tournament_size: int;
  mutation_rate: float;
  num_generations: int;
  num_games: int;
  search_depth: int;
  max_moves: int;
}

let tournament_selection rng population tournament_size =
  let pop_size = Array.length population in
  let best = ref population.(Random.State.int rng pop_size) in
  
  for _ = 2 to tournament_size do
    let candidate = population.(Random.State.int rng pop_size) in
    if candidate.fitness > !best.fitness then
      best := candidate
  done;
  
  !best

let create_initial_population rng pop_size max_depth =
  Array.init pop_size (fun _ -> create_random_program rng max_depth)

let evolve_population rng population elite_size tournament_size mutation_rate max_depth =
  let pop_size = Array.length population in
  
  (* Sort by fitness descending *)
  Array.sort (fun a b -> compare b.fitness a.fitness) population;
  
  (* Create new population *)
  let new_population = Array.make pop_size population.(0) in
  
  (* Keep elite *)
  for i = 0 to elite_size - 1 do
    new_population.(i) <- copy_program population.(i)
  done;
  
  (* Generate rest through crossover and mutation *)
  let idx = ref elite_size in
  while !idx < pop_size do
    let parent1 = tournament_selection rng population tournament_size in
    let parent2 = tournament_selection rng population tournament_size in
    
    let child1, child2 = crossover rng parent1 parent2 in
    
    let child1 = mutate rng child1 mutation_rate max_depth in
    let child2 = mutate rng child2 mutation_rate max_depth in
    
    if !idx < pop_size then begin
      new_population.(!idx) <- child1;
      incr idx
    end;
    
    if !idx < pop_size then begin
      new_population.(!idx) <- child2;
      incr idx
    end
  done;
  
  new_population

let evaluate_population population rng num_games search_depth max_moves =
  Array.iter (fun program ->
    if program.games_played = 0 then
      let _ = evaluate_fitness program rng num_games search_depth max_moves in
      ()
  ) population

let get_best_program population =
  Array.fold_left (fun best prog ->
    if prog.fitness > best.fitness then prog else best
  ) population.(0) population

let get_population_stats population =
  let fitnesses = Array.map (fun p -> p.fitness) population in
  let sum = Array.fold_left (+.) 0.0 fitnesses in
  let avg = sum /. float_of_int (Array.length fitnesses) in
  
  Array.sort compare fitnesses;
  let min_fit = fitnesses.(0) in
  let max_fit = fitnesses.(Array.length fitnesses - 1) in
  
  (avg, min_fit, max_fit)

let run_evolution rng config =
  let { pop_size; max_depth; elite_size; tournament_size; 
        mutation_rate; num_generations; num_games; 
        search_depth; max_moves } = config in
  
  Printf.printf "Creating initial population of %d programs...\n" pop_size;
  let population = create_initial_population rng pop_size max_depth in
  
  Printf.printf "Evaluating initial population...\n";
  evaluate_population population rng num_games search_depth max_moves;
  
  for gen = 1 to num_generations do
    Printf.printf "\nGeneration %d/%d\n" gen num_generations;
    
    let population = evolve_population rng population elite_size 
                       tournament_size mutation_rate max_depth in
    
    evaluate_population population rng num_games search_depth max_moves;
    
    let best = get_best_program population in
    let avg_fit, min_fit, max_fit = get_population_stats population in
    
    Printf.printf "Best fitness: %.2f (avg_score: %.2f, avg_max_tile: %.2f)\n"
      best.fitness best.avg_score best.avg_max_tile;
    Printf.printf "Population fitness - Avg: %.2f, Min: %.2f, Max: %.2f\n"
      avg_fit min_fit max_fit;
    
    flush stdout
  done;
  
  get_best_program population

let default_config = {
  pop_size = 50;
  max_depth = 5;
  elite_size = 5;
  tournament_size = 5;
  mutation_rate = 0.1;
  num_generations = 50;
  num_games = 10;
  search_depth = 2;
  max_moves = 1000;
}