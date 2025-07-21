(* Fast GP evolution using all speedups: LUT + multi-core + node-budget *)

open Gp_2048_lib.Game_fast  (* Use fast game with LUT *)
open Gp_2048_lib.Gp_tree
open Domainslib

(* Global domain pool *)
let num_domains = 6
let pool = Task.setup_pool ~num_domains ()

(* Node-limited expectimax for fast evaluation *)
type search_control = {
  mutable nodes_remaining: int;
  mutable max_depth_reached: int;
}

let rec max_value_limited board program depth control =
  if control.nodes_remaining <= 0 then
    eval_program program board
  else begin
    control.nodes_remaining <- control.nodes_remaining - 1;
    
    if is_game_over board then
      eval_program program board -. 1000000.0
    else if depth = 0 then
      eval_program program board
    else
      let moves = [`Up; `Down; `Left; `Right] in
      let valid_moves = List.filter (fun dir ->
        let new_board = match dir with
          | `Up -> move_up board
          | `Down -> move_down board
          | `Left -> move_left board
          | `Right -> move_right board
        in
        not (Int64.equal board new_board)
      ) moves in
      
      if valid_moves = [] then
        eval_program program board -. 1000000.0
      else
        List.fold_left (fun best_value dir ->
          let new_board = match dir with
            | `Up -> move_up board
            | `Down -> move_down board
            | `Left -> move_left board
            | `Right -> move_right board
          in
          let value = expect_value_limited new_board program depth control in
          max best_value value
        ) neg_infinity valid_moves
  end

and expect_value_limited board program depth control =
  if control.nodes_remaining <= 0 then
    eval_program program board
  else begin
    control.nodes_remaining <- control.nodes_remaining - 1;
    
    let empty_cells = get_empty_cells board in
    if empty_cells = [] then
      max_value_limited board program (depth - 1) control
    else
      let num_empty = List.length empty_cells in
      let cells_to_try = 
        if num_empty > 6 && control.nodes_remaining < num_empty * 10 then
          (* Sample a subset *)
          let n = min 4 num_empty in
          let rec take n lst =
            match n, lst with
            | 0, _ | _, [] -> []
            | n, h::t -> h :: take (n-1) t
          in
          take n empty_cells
        else
          empty_cells
      in
      
      let sum = List.fold_left (fun acc pos ->
        let board_2 = set_cell board pos 1 in
        let board_4 = set_cell board pos 2 in
        acc +. 0.9 *. max_value_limited board_2 program (depth - 1) control
            +. 0.1 *. max_value_limited board_4 program (depth - 1) control
      ) 0.0 cells_to_try in
      sum /. float_of_int (List.length cells_to_try)
  end

let get_best_move_limited board program node_budget =
  let moves = [`Up; `Down; `Left; `Right] in
  let valid_moves = List.filter (fun dir ->
    let new_board = match dir with
      | `Up -> move_up board
      | `Down -> move_down board
      | `Left -> move_left board
      | `Right -> move_right board
    in
    not (Int64.equal board new_board)
  ) moves in
  
  if valid_moves = [] then None
  else
    let nodes_per_move = node_budget / List.length valid_moves in
    let move_values = List.map (fun dir ->
      let new_board = match dir with
        | `Up -> move_up board
        | `Down -> move_down board
        | `Left -> move_left board
        | `Right -> move_right board
      in
      let control = { 
        nodes_remaining = nodes_per_move; 
        max_depth_reached = 0 
      } in
      let value = expect_value_limited new_board program 10 control in
      (dir, value)
    ) valid_moves in
    
    let best_move = List.fold_left (fun (best_dir, best_val) (dir, value) ->
      if value > best_val then (dir, value) else (best_dir, best_val)
    ) (List.hd move_values) (List.tl move_values) in
    
    Some (fst best_move)

(* Play a game with dynamic node budget *)
let play_game_dynamic program rng node_budget_fn max_moves =
  let rec play_loop board score moves =
    if moves >= max_moves || is_game_over board then
      (score, get_max_tile board)
    else
      let empty_count = List.length (get_empty_cells board) in
      let node_budget = node_budget_fn empty_count score in
      
      match get_best_move_limited board program node_budget with
      | None -> (score, get_max_tile board)
      | Some dir ->
        let new_board = match dir with
          | `Up -> move_up board
          | `Down -> move_down board
          | `Left -> move_left board
          | `Right -> move_right board
        in
        let move_score = get_score_for_move board dir in
        let new_board = add_random_tile new_board rng in
        play_loop new_board (score + move_score) (moves + 1)
  in
  
  let initial_board = empty_board |> fun b -> add_random_tile b rng |> fun b -> add_random_tile b rng in
  play_loop initial_board 0 0

(* Evaluate a program with a specific node budget strategy *)
let evaluate_program_with_budget program node_budget_fn num_games =
  let total_score = ref 0 in
  let total_max_tile = ref 0 in
  let rng = Random.State.make [|42|] in
  
  for _ = 1 to num_games do
    let score, max_tile = play_game_dynamic program rng node_budget_fn 1000 in
    total_score := !total_score + score;
    total_max_tile := !total_max_tile + max_tile
  done;
  
  let avg_score = float_of_int !total_score /. float_of_int num_games in
  let avg_max_tile = float_of_int !total_max_tile /. float_of_int num_games in
  (avg_score, avg_max_tile)

(* GP Evolution *)
type individual = {
  program: program;
  mutable fitness: float;
  mutable avg_score: float;
  mutable avg_max_tile: float;
  mutable best_node_budget: string;  (* Name of best strategy *)
}

let create_random_program_wrapper max_depth =
  let rng = Random.State.make_self_init () in
  create_random_program rng max_depth

let tournament_selection population tournament_size =
  let rec select n acc =
    if n = 0 then acc
    else
      let idx = Random.int (Array.length population) in
      select (n-1) (population.(idx) :: acc)
  in
  let tournament = select tournament_size [] in
  List.fold_left (fun best ind ->
    if ind.fitness > best.fitness then ind else best
  ) (List.hd tournament) (List.tl tournament)

let crossover_programs parent1 parent2 =
  let rng = Random.State.make_self_init () in
  let child1, _ = crossover rng parent1.program parent2.program in
  child1

let mutate_program program max_depth =
  let rng = Random.State.make_self_init () in
  mutate rng program 0.2 max_depth

(* Parallel fitness evaluation *)
let evaluate_population population =
  (* Test different node budget strategies *)
  let strategies = [
    ("Fixed_1000", fun _ _ -> 1000);
    ("Score_based", fun _ score -> 1000 + score / 100);
    ("Empty_based", fun empty _ -> 500 + empty * 300);
  ] in
  
  Task.run pool (fun () ->
    Task.parallel_for pool ~start:0 ~finish:(Array.length population - 1)
      ~body:(fun i ->
        let ind = population.(i) in
        
        (* Test each strategy and pick the best *)
        let best_strategy = ref "" in
        let best_fitness = ref neg_infinity in
        let best_avg_score = ref 0.0 in
        let best_avg_max_tile = ref 0.0 in
        
        List.iter (fun (name, budget_fn) ->
          let avg_score, avg_max_tile = 
            evaluate_program_with_budget ind.program budget_fn 5 in
          let fitness = avg_score +. (avg_max_tile ** 2.0) in
          
          if fitness > !best_fitness then begin
            best_strategy := name;
            best_fitness := fitness;
            best_avg_score := avg_score;
            best_avg_max_tile := avg_max_tile
          end
        ) strategies;
        
        ind.fitness <- !best_fitness;
        ind.avg_score <- !best_avg_score;
        ind.avg_max_tile <- !best_avg_max_tile;
        ind.best_node_budget <- !best_strategy
      )
  )

(* Save program with node budget info *)
let save_program_with_budget ind filename =
  (* Determine optimal node budget upper bound based on strategy *)
  let node_budget_max = match ind.best_node_budget with
    | "Fixed_1000" -> 1000
    | "Score_based" -> 5000  (* Max expected: 1000 + 4000/100 *)
    | "Empty_based" -> 5300  (* Max expected: 500 + 16*300 *)
    | _ -> 1000
  in
  
  let nodes_array = ind.program.nodes
    |> Array.to_list
    |> List.map Gp_2048_lib.Gp_tree_json.node_to_string
    |> List.map (fun s -> "\"" ^ s ^ "\"")
    |> String.concat ", "
  in
  
  let json = Printf.sprintf {|{
  "nodes": [%s],
  "node_budget_max": %d,
  "fitness": %.2f,
  "avg_score": %.2f,
  "avg_max_tile": %.2f
}|}
    nodes_array
    node_budget_max
    ind.fitness
    ind.avg_score
    ind.avg_max_tile
  in
  
  let oc = open_out filename in
  output_string oc json;
  close_out oc

(* Main evolution *)
let evolve_gp ~generations ~pop_size ~tournament_size ~mutation_prob ~crossover_prob ~max_depth =
  Printf.printf "Starting GP evolution with %d cores...\n" num_domains;
  Printf.printf "Population: %d, Generations: %d\n\n" pop_size generations;
  
  (* Initialize population *)
  let population = Array.init pop_size (fun _ ->
    { program = create_random_program_wrapper max_depth;
      fitness = 0.0;
      avg_score = 0.0;
      avg_max_tile = 0.0;
      best_node_budget = "Fixed_1000" }
  ) in
  
  (* Evolution loop *)
  for gen = 1 to generations do
    Printf.printf "Generation %d/%d\n" gen generations;
    
    (* Evaluate fitness *)
    Printf.printf "  Evaluating population...\n";
    flush stdout;
    evaluate_population population;
    
    (* Sort by fitness *)
    Array.sort (fun a b -> compare b.fitness a.fitness) population;
    
    (* Print best *)
    let best = population.(0) in
    Printf.printf "  Best: fitness=%.2f, score=%.0f, max_tile=%.0f, strategy=%s\n"
      best.fitness best.avg_score best.avg_max_tile best.best_node_budget;
    Printf.printf "  Program: %s\n" (program_to_string best.program);
    flush stdout;
    
    (* Save best every 10 generations *)
    if gen mod 10 = 0 then begin
      let filename = Printf.sprintf "python/models/evolved_gen%d.json" gen in
      save_program_with_budget best filename;
      Printf.printf "  Saved to %s\n" filename
    end;
    
    (* Create next generation *)
    if gen < generations then begin
      let new_population = Array.make pop_size population.(0) in
      
      (* Elitism - keep best 10% *)
      let elite_size = pop_size / 10 in
      for i = 0 to elite_size - 1 do
        new_population.(i) <- population.(i)
      done;
      
      (* Fill rest with offspring *)
      for i = elite_size to pop_size - 1 do
        let parent1 = tournament_selection population tournament_size in
        
        let offspring_program = 
          if Random.float 1.0 < crossover_prob then
            let parent2 = tournament_selection population tournament_size in
            crossover_programs parent1 parent2
          else
            parent1.program
        in
        
        let offspring_program = 
          if Random.float 1.0 < mutation_prob then
            mutate_program offspring_program max_depth
          else
            offspring_program
        in
        
        new_population.(i) <- {
          program = offspring_program;
          fitness = 0.0;
          avg_score = 0.0;
          avg_max_tile = 0.0;
          best_node_budget = "Fixed_1000"
        }
      done;
      
      Array.blit new_population 0 population 0 pop_size
    end
  done;
  
  (* Save final best *)
  let best = population.(0) in
  let filename = "python/models/best_evolved.json" in
  save_program_with_budget best filename;
  Printf.printf "\nEvolution complete! Best program saved to %s\n" filename;
  Printf.printf "Best fitness: %.2f (score=%.0f, max_tile=%.0f)\n" 
    best.fitness best.avg_score best.avg_max_tile

let () =
  init_tables ();
  
  (* Ensure models directory exists *)
  let models_dir = "python/models" in
  if not (Sys.file_exists models_dir) then
    Unix.mkdir models_dir 0o755;
  
  (* Run evolution *)
  evolve_gp
    ~generations:30
    ~pop_size:50
    ~tournament_size:5
    ~mutation_prob:0.2
    ~crossover_prob:0.8
    ~max_depth:5;
    
  (* Cleanup *)
  Task.teardown_pool pool