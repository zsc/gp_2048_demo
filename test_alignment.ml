open Gp_2048_lib.Game
open Gp_2048_lib.Gp_tree
open Gp_2048_lib.Expectimax

let test_bit_operations () =
  Printf.printf "Testing bit operations alignment...\n";
  
  (* Test empty board *)
  assert (empty_board = 0L);
  
  (* Test set_cell and get_cell *)
  let board = set_cell empty_board 0 1 in
  assert (get_cell board 0 = 1);
  assert (get_cell board 1 = 0);
  
  let board = set_cell board 5 3 in
  assert (get_cell board 5 = 3);
  
  (* Test row operations *)
  let board = Int64.of_string "0x0000000000001234" in
  assert (get_row board 0 = 0x1234L);
  
  (* Test transpose - critical for vertical moves *)
  let board = Int64.of_string "0x1234567890ABCDEF" in
  let transposed = transpose board in
  let expected = Int64.of_string "0x159D26AE37BF48CF" in
  Printf.printf "Original:   %016Lx\n" board;
  Printf.printf "Transposed: %016Lx\n" transposed;
  Printf.printf "Expected:   %016Lx\n" expected;
  assert (transposed = expected);
  
  Printf.printf "Bit operations tests passed!\n\n"

let test_move_operations () =
  Printf.printf "Testing move operations...\n";
  
  (* Test simple left move *)
  let board = Int64.of_string "0x0000000000001021" in (* [1,0,2,1] in bottom row *)
  let moved = move_left board in
  let expected = Int64.of_string "0x0000000000000012" in (* [1,2,0,0] *)
  Printf.printf "Left move: %016Lx -> %016Lx (expected %016Lx)\n" board moved expected;
  assert (moved = expected);
  
  (* Test merge in left move *)
  let board = Int64.of_string "0x0000000000001011" in (* [1,0,1,1] in bottom row *)
  let moved = move_left board in
  let expected = Int64.of_string "0x0000000000000021" in (* [2,1,0,0] *)
  Printf.printf "Left merge: %016Lx -> %016Lx (expected %016Lx)\n" board moved expected;
  assert (moved = expected);
  
  (* Test score calculation *)
  let score = get_score_for_move board `Left in
  Printf.printf "Score for merge: %d (expected 4)\n" score;
  assert (score = 4); (* 2^2 = 4 *)
  
  Printf.printf "Move operations tests passed!\n\n"

let test_evaluation_functions () =
  Printf.printf "Testing evaluation functions...\n";
  
  (* Create a test board *)
  let board = ref empty_board in
  board := set_cell !board 0 1;  (* 2 *)
  board := set_cell !board 1 2;  (* 4 *)
  board := set_cell !board 4 3;  (* 8 *)
  board := set_cell !board 5 4;  (* 16 *)
  
  (* Test NumEmptyCells *)
  let empty_count = count_empty_cells !board in
  Printf.printf "Empty cells: %d (expected 12)\n" empty_count;
  assert (empty_count = 12);
  
  (* Test MaxTileValue *)
  let max_tile = get_max_tile !board in
  Printf.printf "Max tile: %d (expected 16)\n" max_tile;
  assert (max_tile = 16);
  
  (* Test MonotonicityScore - should be negative *)
  let mono_score = monotonicity_score !board in
  Printf.printf "Monotonicity score: %.2f (should be negative)\n" mono_score;
  assert (mono_score < 0.0);
  
  (* Test SmoothnessScore - should be negative *)
  let smooth_score = smoothness_score !board in
  Printf.printf "Smoothness score: %.2f (should be negative)\n" smooth_score;
  assert (smooth_score < 0.0);
  
  Printf.printf "Evaluation functions tests passed!\n\n"

let test_gp_tree_evaluation () =
  Printf.printf "Testing GP tree evaluation...\n";
  
  let board = ref empty_board in
  board := set_cell !board 0 1;
  board := set_cell !board 1 2;
  
  (* Test simple constant *)
  let prog1 = { nodes = [|Constant 42.0|]; fitness = 0.0; 
                games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 } in
  let result1 = eval prog1 !board in
  Printf.printf "Constant eval: %.2f (expected 42.00)\n" result1;
  assert (abs_float (result1 -. 42.0) < 0.001);
  
  (* Test addition *)
  let prog2 = { nodes = [|Add; Constant 10.0; Constant 20.0|]; 
                fitness = 0.0; games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 } in
  let result2 = eval prog2 !board in
  Printf.printf "Add eval: %.2f (expected 30.00)\n" result2;
  assert (abs_float (result2 -. 30.0) < 0.001);
  
  (* Test SafeDiv *)
  let prog3 = { nodes = [|SafeDiv; Constant 10.0; Constant 0.0|]; 
                fitness = 0.0; games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 } in
  let result3 = eval prog3 !board in
  Printf.printf "SafeDiv by zero: %.2f (expected 1.00)\n" result3;
  assert (abs_float (result3 -. 1.0) < 0.001);
  
  (* Test IfLTE *)
  let prog4 = { nodes = [|IfLTE; Constant 5.0; Constant 10.0; 
                          Constant 100.0; Constant 200.0|]; 
                fitness = 0.0; games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 } in
  let result4 = eval prog4 !board in
  Printf.printf "IfLTE eval: %.2f (expected 100.00)\n" result4;
  assert (abs_float (result4 -. 100.0) < 0.001);
  
  Printf.printf "GP tree evaluation tests passed!\n\n"

let test_random_tile_generation () =
  Printf.printf "Testing random tile generation...\n";
  
  let rng = Random.State.make [|42|] in
  let board = empty_board in
  
  (* Add 100 random tiles and check distribution *)
  let count_2 = ref 0 in
  let count_4 = ref 0 in
  
  for _ = 1 to 100 do
    let new_board = add_random_tile board rng in
    let empty_cells = get_empty_cells board in
    let added_cell = List.find (fun idx -> 
      get_cell new_board idx <> 0) empty_cells in
    let value = get_cell new_board added_cell in
    if value = 1 then incr count_2
    else if value = 2 then incr count_4
    else assert false
  done;
  
  Printf.printf "Tile distribution: 2s=%d, 4s=%d (expected ~90, ~10)\n" !count_2 !count_4;
  assert (!count_2 > 80 && !count_2 < 100);
  assert (!count_4 > 0 && !count_4 < 20);
  
  Printf.printf "Random tile generation tests passed!\n\n"

let test_expectimax_consistency () =
  Printf.printf "Testing expectimax consistency...\n";
  
  let rng = Random.State.make [|42|] in
  let program = create_random_program rng 3 in
  
  let board = empty_board in
  let board = add_random_tile board rng in
  let board = add_random_tile board rng in
  
  (* Test that same board and program give same result *)
  let result1 = gp_max_value board program 1 in
  let result2 = gp_max_value board program 1 in
  Printf.printf "Expectimax determinism: %.6f == %.6f\n" result1 result2;
  assert (abs_float (result1 -. result2) < 0.0001);
  
  (* Test that game can be played *)
  let score, max_tile = play_game program rng 1 100 in
  Printf.printf "Test game result: score=%d, max_tile=%d\n" score max_tile;
  assert (score >= 0);
  assert (max_tile >= 4);
  
  Printf.printf "Expectimax consistency tests passed!\n\n"

let () =
  test_bit_operations ();
  test_move_operations ();
  test_evaluation_functions ();
  test_gp_tree_evaluation ();
  test_random_tile_generation ();
  test_expectimax_consistency ();
  Printf.printf "All tests passed! ✓\n"