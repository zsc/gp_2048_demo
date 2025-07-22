#!/bin/bash
# Comprehensive training script to generate multiple high-quality models

echo "=== 2048 GP Model Training Suite ==="
echo "Training multiple models with different configurations..."
echo ""

# Ensure models directory exists
mkdir -p python/models

# Backup existing models
if [ "$(ls -A python/models/)" ]; then
    echo "Backing up existing models..."
    mkdir -p python/models/backup_$(date +%Y%m%d_%H%M%S)
    cp python/models/*.json python/models/backup_$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
fi

# Build the project
echo "Building OCaml project..."
dune build

# Function to run evolution and save with custom name
run_evolution() {
    local name=$1
    local generations=$2
    local pop_size=$3
    local description=$4
    
    echo ""
    echo "Training model: $name"
    echo "Configuration: $description"
    echo "Generations: $generations, Population: $pop_size"
    
    # Run the evolution
    dune exec experiments/gp_evolution_fast.exe > "training_${name}.log" 2>&1
    
    # Find the latest generated model and rename it
    latest_model=$(ls -t python/models/best_program_gen*.json 2>/dev/null | head -1)
    if [ -f "$latest_model" ]; then
        mv "$latest_model" "python/models/${name}.json"
        echo "Model saved as: python/models/${name}.json"
        
        # Add description to the JSON
        python3 -c "
import json
with open('python/models/${name}.json', 'r') as f:
    data = json.load(f)
data['description'] = '$description'
data['model_name'] = '$name'
with open('python/models/${name}.json', 'w') as f:
    json.dump(data, f, indent=2)
"
    else
        echo "Warning: No model generated for $name"
    fi
}

# Train different model configurations
echo ""
echo "Starting training runs..."

# 1. Speed-focused model (100-500 nodes)
echo "=== Training Speed Models ==="
run_evolution "speed_demon_v2" 20 60 "Ultra-fast play optimized for speed (100-500 nodes)"

# 2. Balanced models (1000 nodes)
echo ""
echo "=== Training Balanced Models ==="
run_evolution "balanced_warrior" 30 50 "Balanced play with moderate search (1000 nodes)"

# 3. Deep search model (5000 nodes)
echo ""
echo "=== Training Deep Search Models ==="
run_evolution "deep_strategist" 25 40 "Deep strategic search (5000 nodes)"

# 4. Run the leaderboard evolution for comparison
echo ""
echo "=== Running Leaderboard Evolution ==="
dune exec experiments/gp_evolution_leaderboard.exe > training_leaderboard.log 2>&1

# 5. Evaluate all models
echo ""
echo "=== Evaluating All Models ==="
echo "Running evaluation script..."

# Create evaluation script
cat > evaluate_all_models.ml << 'EOF'
open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Gp_tree_json

(* Evaluate a model file *)
let evaluate_model_file filename =
  try
    let ic = open_in filename in
    let json_string = really_input_string ic (in_channel_length ic) in
    close_in ic;
    
    match parse_program_from_json json_string with
    | Ok (program, node_budget) ->
        Printf.printf "\nEvaluating: %s\n" filename;
        Printf.printf "Node budget: %d\n" node_budget;
        
        (* Play 20 games *)
        let scores = ref [] in
        let tiles = ref [] in
        
        for i = 0 to 19 do
          let rng = Random.State.make [|42 + i|] in
          let score, max_tile = Gp_2048_lib.Expectimax_aligned.play_game program 2 500 rng in
          scores := score :: !scores;
          tiles := max_tile :: !tiles
        done;
        
        let avg_score = (List.fold_left (+) 0 !scores) / 20 in
        let max_score = List.fold_left max 0 !scores in
        let avg_tile = (List.fold_left (+) 0 !tiles) / 20 in
        let max_tile = List.fold_left max 0 !tiles in
        
        Printf.printf "Average score: %d\n" avg_score;
        Printf.printf "Max score: %d\n" max_score;
        Printf.printf "Average max tile: %d\n" avg_tile;
        Printf.printf "Best tile: %d\n" max_tile;
        
        (filename, avg_score, max_score, avg_tile, max_tile)
        
    | Error msg ->
        Printf.printf "Error parsing %s: %s\n" filename msg;
        (filename, 0, 0, 0, 0)
  with
  | Sys_error msg ->
      Printf.printf "Error reading %s: %s\n" filename msg;
      (filename, 0, 0, 0, 0)

let () =
  init_tables ();
  
  (* Find all JSON models *)
  let models_dir = "python/models" in
  let models = Sys.readdir models_dir
    |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f ".json")
    |> List.map (fun f -> Filename.concat models_dir f)
  in
  
  Printf.printf "Found %d models to evaluate\n" (List.length models);
  
  (* Evaluate all models *)
  let results = List.map evaluate_model_file models in
  
  (* Sort by average score *)
  let sorted = List.sort (fun (_, a1, _, _, _) (_, a2, _, _, _) -> compare a2 a1) results in
  
  (* Print leaderboard *)
  Printf.printf "\n\n=== MODEL LEADERBOARD ===\n";
  Printf.printf "%-30s %10s %10s %10s %10s\n" "Model" "Avg Score" "Max Score" "Avg Tile" "Best Tile";
  Printf.printf "%s\n" (String.make 80 '-');
  
  List.iter (fun (name, avg_score, max_score, avg_tile, max_tile) ->
    let basename = Filename.basename name in
    Printf.printf "%-30s %10d %10d %10d %10d\n" basename avg_score max_score avg_tile max_tile
  ) sorted;
  
  (* Save leaderboard to file *)
  let oc = open_out "model_leaderboard.txt" in
  List.iter (fun (name, avg_score, max_score, avg_tile, max_tile) ->
    Printf.fprintf oc "%s,%d,%d,%d,%d\n" (Filename.basename name) avg_score max_score avg_tile max_tile
  ) sorted;
  close_out oc;
  
  Printf.printf "\nLeaderboard saved to model_leaderboard.txt\n"
EOF

# Compile and run evaluation
echo "Compiling evaluation script..."
ocamlopt -I _build/default/lib/.gp_2048_lib.objs/byte \
         _build/default/lib/gp_2048_lib.cmxa \
         evaluate_all_models.ml -o evaluate_all_models

echo "Running evaluation..."
./evaluate_all_models

# Cleanup
rm -f evaluate_all_models.ml evaluate_all_models.cm* evaluate_all_models.o evaluate_all_models

echo ""
echo "=== Training Complete ==="
echo "Check python/models/ for generated models"
echo "Check model_leaderboard.txt for performance comparison"
echo "Training logs saved as training_*.log"