open Gp_2048_lib

let benchmark_evaluations num_boards =
  let rng = Random.State.make [|42|] in
  
  (* Generate random boards *)
  let boards = Array.init num_boards (fun _ ->
    let board = ref Game.empty_board in
    let num_tiles = 4 + Random.State.int rng 10 in
    for _ = 1 to num_tiles do
      board := Game.add_random_tile !board rng
    done;
    !board
  ) in
  
  (* Benchmark original implementation *)
  let start_orig = Unix.gettimeofday () in
  let orig_mono_sum = ref 0.0 in
  let orig_smooth_sum = ref 0.0 in
  
  for i = 0 to num_boards - 1 do
    orig_mono_sum := !orig_mono_sum +. Game.monotonicity_score boards.(i);
    orig_smooth_sum := !orig_smooth_sum +. Game.smoothness_score boards.(i)
  done;
  
  let time_orig = Unix.gettimeofday () -. start_orig in
  
  (* Benchmark LUT implementation *)
  let start_lut = Unix.gettimeofday () in
  let lut_mono_sum = ref 0.0 in
  let lut_smooth_sum = ref 0.0 in
  
  for i = 0 to num_boards - 1 do
    lut_mono_sum := !lut_mono_sum +. Game_fast.monotonicity_score boards.(i);
    lut_smooth_sum := !lut_smooth_sum +. Game_fast.smoothness_score boards.(i)
  done;
  
  let time_lut = Unix.gettimeofday () -. start_lut in
  
  (* Verify correctness *)
  let mono_diff = abs_float (!orig_mono_sum -. !lut_mono_sum) in
  let smooth_diff = abs_float (!orig_smooth_sum -. !lut_smooth_sum) in
  
  Printf.printf "Evaluation Function Benchmark (%d boards):\n" num_boards;
  Printf.printf "----------------------------------------\n";
  Printf.printf "Original implementation: %.3f seconds\n" time_orig;
  Printf.printf "LUT implementation: %.3f seconds\n" time_lut;
  Printf.printf "Speedup: %.1fx\n\n" (time_orig /. time_lut);
  
  Printf.printf "Correctness check:\n";
  Printf.printf "  Monotonicity difference: %.6f\n" mono_diff;
  Printf.printf "  Smoothness difference: %.6f\n" smooth_diff;
  
  if mono_diff > 0.001 || smooth_diff > 0.001 then
    Printf.printf "  WARNING: Results differ!\n"
  else
    Printf.printf "  ✓ Results match\n"

let benchmark_full_game_eval () =
  let rng = Random.State.make [|42|] in
  
  (* Simple GP program *)
  let program = {
    Gp_tree.nodes = [| Add; Mul; MonotonicityScore; SmoothnessScore; NumEmptyCells |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  (* Generate test boards *)
  let num_boards = 10000 in
  let boards = Array.init num_boards (fun _ ->
    let board = ref Game.empty_board in
    let num_tiles = 4 + Random.State.int rng 10 in
    for _ = 1 to num_tiles do
      board := Game.add_random_tile !board rng
    done;
    !board
  ) in
  
  (* Create modified eval function that uses Game_fast *)
  let eval_fast (program : Gp_tree.program) board =
    let safe_div x y = if abs_float y < 1e-6 then 1.0 else x /. y in
    let rec eval_node idx =
      if idx >= Array.length program.nodes then (0.0, idx)
      else
        match program.nodes.(idx) with
        | Add ->
          let v1, idx1 = eval_node (idx + 1) in
          let v2, idx2 = eval_node idx1 in
          (v1 +. v2, idx2)
        | Sub ->
          let v1, idx1 = eval_node (idx + 1) in
          let v2, idx2 = eval_node idx1 in
          (v1 -. v2, idx2)
        | Mul ->
          let v1, idx1 = eval_node (idx + 1) in
          let v2, idx2 = eval_node idx1 in
          (v1 *. v2, idx2)
        | SafeDiv ->
          let v1, idx1 = eval_node (idx + 1) in
          let v2, idx2 = eval_node idx1 in
          (safe_div v1 v2, idx2)
        | IfLTE ->
          let v1, idx1 = eval_node (idx + 1) in
          let v2, idx2 = eval_node idx1 in
          let v3, idx3 = eval_node idx2 in
          let v4, idx4 = eval_node idx3 in
          ((if v1 <= v2 then v3 else v4), idx4)
        | Constant c -> (c, idx + 1)
        | NumEmptyCells -> 
          (float_of_int (Game_fast.count_empty_cells board), idx + 1)
        | MaxTileValue ->
          let max_log2 = ref 0 in
          for i = 0 to 15 do
            let cell = Game_fast.get_cell board i in
            if cell > !max_log2 then max_log2 := cell
          done;
          (float_of_int !max_log2, idx + 1)
        | MonotonicityScore ->
          (Game_fast.monotonicity_score board, idx + 1)
        | SmoothnessScore ->
          (Game_fast.smoothness_score board, idx + 1)
    in
    let value, _ = eval_node 0 in
    value
  in
  
  (* Benchmark original *)
  let start_orig = Unix.gettimeofday () in
  let orig_sum = ref 0.0 in
  for i = 0 to num_boards - 1 do
    orig_sum := !orig_sum +. Gp_tree.eval program boards.(i)
  done;
  let time_orig = Unix.gettimeofday () -. start_orig in
  
  (* Benchmark with LUT *)
  let start_lut = Unix.gettimeofday () in
  let lut_sum = ref 0.0 in
  for i = 0 to num_boards - 1 do
    lut_sum := !lut_sum +. eval_fast program boards.(i)
  done;
  let time_lut = Unix.gettimeofday () -. start_lut in
  
  Printf.printf "\nFull GP Evaluation Benchmark (%d evaluations):\n" num_boards;
  Printf.printf "---------------------------------------------\n";
  Printf.printf "Original: %.3f seconds (%.0f evals/sec)\n" 
    time_orig (float_of_int num_boards /. time_orig);
  Printf.printf "With LUT: %.3f seconds (%.0f evals/sec)\n" 
    time_lut (float_of_int num_boards /. time_lut);
  Printf.printf "Speedup: %.1fx\n" (time_orig /. time_lut)

let () =
  Game.init_tables ();
  Game_fast.init_tables ();
  
  Printf.printf "Benchmarking evaluation functions with lookup tables...\n\n";
  
  benchmark_evaluations 100000;
  Printf.printf "\n";
  benchmark_full_game_eval ()