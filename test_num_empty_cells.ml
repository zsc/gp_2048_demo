open Gp_2048_lib.Game_fast
open Gp_2048_lib.Gp_tree

(* Helper to create board from array of tile values (not log2) *)
let create_board_from_tiles tiles =
  let board = ref 0L in
  Array.iteri (fun i tile ->
    let log2_val = 
      if tile = 0 then 0
      else int_of_float (log (float_of_int tile) /. log 2.0)
    in
    board := set_cell !board i log2_val
  ) tiles;
  !board

(* Helper to print board *)
let print_board board =
  Printf.printf "Board:\n";
  for row = 0 to 3 do
    for col = 0 to 3 do
      let idx = row * 4 + col in
      let cell = get_cell board idx in
      let tile = if cell = 0 then 0 else 1 lsl cell in
      Printf.printf "%5d " tile
    done;
    Printf.printf "\n"
  done

(* Test NumEmptyCells *)
let test_num_empty_cells () =
  Printf.printf "=== Testing NumEmptyCells Accuracy ===\n\n";
  
  (* Create program with just NumEmptyCells *)
  let program = {
    nodes = [| NumEmptyCells |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  (* Test cases: (board tiles, expected empty count) *)
  let test_cases = [
    (* Empty board *)
    ([|0;0;0;0; 0;0;0;0; 0;0;0;0; 0;0;0;0|], 16);
    
    (* Full board *)
    ([|2;4;8;16; 32;64;128;256; 512;1024;2048;4096; 8;16;32;64|], 0);
    
    (* Half empty *)
    ([|2;0;4;0; 0;8;0;16; 32;0;64;0; 0;128;0;256|], 8);
    
    (* Only corners filled *)
    ([|2;0;0;4; 0;0;0;0; 0;0;0;0; 8;0;0;16|], 12);
    
    (* Single tile *)
    ([|2048;0;0;0; 0;0;0;0; 0;0;0;0; 0;0;0;0|], 15);
    
    (* Two tiles (game start) *)
    ([|0;0;0;0; 0;2;0;0; 0;0;0;0; 0;0;4;0|], 14);
    
    (* Typical mid-game *)
    ([|0;2;4;8; 0;0;16;32; 0;0;0;64; 0;0;0;128|], 9);
    
    (* Near end-game *)
    ([|2;4;8;16; 32;64;128;256; 512;1024;2048;0; 8;16;32;0|], 2);
  ] in
  
  let all_correct = ref true in
  
  List.iteri (fun i (tiles, expected) ->
    let board = create_board_from_tiles tiles in
    
    (* Count using count_empty_cells directly *)
    let actual_count = count_empty_cells board in
    
    (* Evaluate using NumEmptyCells node *)
    let eval_result = eval_program program board in
    let eval_count = int_of_float eval_result in
    
    Printf.printf "Test %d:\n" (i + 1);
    print_board board;
    Printf.printf "Expected empty cells: %d\n" expected;
    Printf.printf "count_empty_cells:    %d %s\n" actual_count 
      (if actual_count = expected then "✓" else "✗");
    Printf.printf "NumEmptyCells eval:   %d %s\n" eval_count
      (if eval_count = expected then "✓" else "✗");
    
    if actual_count <> expected || eval_count <> expected then begin
      all_correct := false;
      Printf.printf "ERROR: Mismatch!\n"
    end;
    
    Printf.printf "\n"
  ) test_cases;
  
  if !all_correct then
    Printf.printf "✅ All tests passed! NumEmptyCells is accurate.\n"
  else
    Printf.printf "❌ Some tests failed! NumEmptyCells has accuracy issues.\n"

(* Also test with random boards *)
let test_random_boards () =
  Printf.printf "\n=== Testing with Random Boards ===\n\n";
  
  let rng = Random.State.make [|42|] in
  let program = {
    nodes = [| NumEmptyCells |];
    fitness = 0.0;
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  } in
  
  for test = 1 to 5 do
    (* Create random board *)
    let board = ref empty_board in
    let num_tiles = Random.State.int rng 16 in (* 0 to 15 tiles *)
    
    (* Add random tiles *)
    for _ = 1 to num_tiles do
      let empty_cells = get_empty_cells !board in
      if empty_cells <> [] then begin
        let idx = List.nth empty_cells (Random.State.int rng (List.length empty_cells)) in
        let value = if Random.State.float rng 1.0 < 0.9 then 1 else 2 in (* 90% 2, 10% 4 *)
        board := set_cell !board idx value
      end
    done;
    
    let empty_count = count_empty_cells !board in
    let eval_count = int_of_float (eval_program program !board) in
    
    Printf.printf "Random test %d:\n" test;
    print_board !board;
    Printf.printf "Empty cells: %d (count_empty_cells) vs %d (NumEmptyCells)\n" 
      empty_count eval_count;
    Printf.printf "Match: %s\n\n" (if empty_count = eval_count then "✓" else "✗")
  done

(* Test edge cases *)
let test_edge_cases () =
  Printf.printf "\n=== Testing Edge Cases ===\n\n";
  
  (* Test with maximum tile values *)
  let max_board = create_board_from_tiles 
    [|131072;65536;32768;16384; 8192;4096;2048;1024; 512;256;128;64; 32;16;8;4|] in
  
  Printf.printf "Maximum value board:\n";
  print_board max_board;
  Printf.printf "Empty cells: %d\n\n" (count_empty_cells max_board);
  
  (* Test specific patterns *)
  let diagonal = create_board_from_tiles
    [|2;0;0;0; 0;4;0;0; 0;0;8;0; 0;0;0;16|] in
    
  Printf.printf "Diagonal pattern:\n";
  print_board diagonal;
  Printf.printf "Empty cells: %d (expected 12)\n\n" (count_empty_cells diagonal)

let () =
  init_tables ();
  test_num_empty_cells ();
  test_random_boards ();
  test_edge_cases ()