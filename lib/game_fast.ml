(* Enhanced game module with lookup tables for evaluation functions *)

open Int64

type board = int64

let empty_board = 0L

let row_mask = 0xFFFFL
let cell_mask = 0xFL

let get_row board row_idx =
  Int64.(logand (shift_right_logical board (row_idx * 16)) row_mask)

let set_row board row_idx row =
  let mask = Int64.(lognot (shift_left row_mask (row_idx * 16))) in
  let cleared = Int64.logand board mask in
  Int64.logor cleared (Int64.shift_left row (row_idx * 16))

let get_cell board idx =
  Int64.(to_int (logand (shift_right_logical board (idx * 4)) cell_mask))

let set_cell board idx value =
  let mask = Int64.(lognot (shift_left cell_mask (idx * 4))) in
  let cleared = Int64.logand board mask in
  Int64.logor cleared (Int64.shift_left (of_int value) (idx * 4))

(* Existing lookup tables *)
let left_table = Array.make 65536 0
let right_table = Array.make 65536 0
let score_table = Array.make 65536 0

(* New lookup tables for evaluation functions *)
let monotonicity_table = Array.make 65536 0.0
let smoothness_table = Array.make 65536 0.0

let load_table_from_file filename =
  let ic = open_in_bin filename in
  let table = Array.make 65536 0 in
  for i = 0 to 65535 do
    let b0 = input_byte ic in
    let b1 = input_byte ic in
    let b2 = input_byte ic in
    let b3 = input_byte ic in
    table.(i) <- b0 lor (b1 lsl 8) lor (b2 lsl 16) lor (b3 lsl 24)
  done;
  close_in ic;
  table

(* Compute monotonicity score for a single row *)
let compute_row_monotonicity row =
  let cells = [|
    row land 0xF;
    (row lsr 4) land 0xF;
    (row lsr 8) land 0xF;
    (row lsr 12) land 0xF
  |] in
  
  let inc = ref 0.0 in
  let dec = ref 0.0 in
  
  for i = 0 to 2 do
    if cells.(i) > cells.(i + 1) then
      dec := !dec +. float_of_int (cells.(i) - cells.(i + 1))
    else if cells.(i) < cells.(i + 1) then
      inc := !inc +. float_of_int (cells.(i + 1) - cells.(i))
  done;
  
  Stdlib.max !inc !dec

(* Compute smoothness score for a single row *)
let compute_row_smoothness row =
  let cells = [|
    row land 0xF;
    (row lsr 4) land 0xF;
    (row lsr 8) land 0xF;
    (row lsr 12) land 0xF
  |] in
  
  let score = ref 0.0 in
  
  for i = 0 to 2 do
    if cells.(i) <> 0 && cells.(i + 1) <> 0 then
      score := !score -. abs_float (float_of_int cells.(i) -. float_of_int cells.(i + 1))
  done;
  
  !score

(* Initialize all lookup tables *)
let init_tables () =
  (* Load existing tables *)
  let left = load_table_from_file "left_table.bin" in
  let right = load_table_from_file "right_table.bin" in
  let score = load_table_from_file "score_table.bin" in
  
  for i = 0 to 65535 do
    left_table.(i) <- left.(i);
    right_table.(i) <- right.(i);
    score_table.(i) <- score.(i);
    
    (* Compute evaluation function tables *)
    monotonicity_table.(i) <- compute_row_monotonicity i;
    smoothness_table.(i) <- compute_row_smoothness i
  done

let transpose board =
  let a0 = Int64.(logand board 0xF0F00F0FF0F00F0FL) in
  let a1 = Int64.(logand board 0x0000F0F00000F0F0L) in
  let a2 = Int64.(logand board 0x0F0F00000F0F0000L) in
  let a = Int64.(logor a0 (logor (shift_left a1 12) (shift_right_logical a2 12))) in
  
  let b0 = Int64.(logand a 0xFF00FF0000FF00FFL) in
  let b1 = Int64.(logand a 0x00FF00FF00000000L) in
  let b2 = Int64.(logand a 0x00000000FF00FF00L) in
  Int64.(logor b0 (logor (shift_right_logical b1 24) (shift_left b2 24)))

let move_left board =
  let b0 = get_row board 0 |> Int64.to_int |> (Array.get left_table) |> Int64.of_int in
  let b1 = get_row board 1 |> Int64.to_int |> (Array.get left_table) |> Int64.of_int in
  let b2 = get_row board 2 |> Int64.to_int |> (Array.get left_table) |> Int64.of_int in
  let b3 = get_row board 3 |> Int64.to_int |> (Array.get left_table) |> Int64.of_int in
  Int64.(logor b0 (logor (shift_left b1 16) (logor (shift_left b2 32) (shift_left b3 48))))

let move_right board =
  let b0 = get_row board 0 |> Int64.to_int |> (Array.get right_table) |> Int64.of_int in
  let b1 = get_row board 1 |> Int64.to_int |> (Array.get right_table) |> Int64.of_int in
  let b2 = get_row board 2 |> Int64.to_int |> (Array.get right_table) |> Int64.of_int in
  let b3 = get_row board 3 |> Int64.to_int |> (Array.get right_table) |> Int64.of_int in
  Int64.(logor b0 (logor (shift_left b1 16) (logor (shift_left b2 32) (shift_left b3 48))))

let move_up board =
  transpose board |> move_left |> transpose

let move_down board =
  transpose board |> move_right |> transpose

let get_score_for_move board direction =
  let compute_row_scores b =
    let s0 = get_row b 0 |> Int64.to_int |> (Array.get score_table) in
    let s1 = get_row b 1 |> Int64.to_int |> (Array.get score_table) in
    let s2 = get_row b 2 |> Int64.to_int |> (Array.get score_table) in
    let s3 = get_row b 3 |> Int64.to_int |> (Array.get score_table) in
    s0 + s1 + s2 + s3
  in
  match direction with
  | `Left | `Right -> compute_row_scores board
  | `Up | `Down -> compute_row_scores (transpose board)

let count_empty_cells board =
  let count = ref 0 in
  for i = 0 to 15 do
    if get_cell board i = 0 then incr count
  done;
  !count

let get_empty_cells board =
  let cells = ref [] in
  for i = 15 downto 0 do
    if get_cell board i = 0 then cells := i :: !cells
  done;
  !cells

let add_random_tile board rng =
  let empty_cells = get_empty_cells board in
  match empty_cells with
  | [] -> board
  | cells ->
    let idx = List.nth cells (Random.State.int rng (List.length cells)) in
    let value = if Random.State.float rng 1.0 < 0.9 then 1 else 2 in
    set_cell board idx value

let get_max_tile board =
  let max_tile = ref 0 in
  for i = 0 to 15 do
    let cell = get_cell board i in
    if cell > !max_tile then max_tile := cell
  done;
  if !max_tile = 0 then 0 else 1 lsl !max_tile

let is_game_over board =
  if count_empty_cells board > 0 then false
  else
    let b_left = move_left board in
    let b_right = move_right board in
    let b_up = move_up board in
    let b_down = move_down board in
    Int64.(equal board b_left && equal board b_right && 
           equal board b_up && equal board b_down)

(* Fast monotonicity score using lookup tables *)
let monotonicity_score board =
  (* Sum row scores *)
  let row_score = 
    monotonicity_table.(get_row board 0 |> Int64.to_int) +.
    monotonicity_table.(get_row board 1 |> Int64.to_int) +.
    monotonicity_table.(get_row board 2 |> Int64.to_int) +.
    monotonicity_table.(get_row board 3 |> Int64.to_int)
  in
  
  (* Sum column scores (use transposed board) *)
  let t_board = transpose board in
  let col_score = 
    monotonicity_table.(get_row t_board 0 |> Int64.to_int) +.
    monotonicity_table.(get_row t_board 1 |> Int64.to_int) +.
    monotonicity_table.(get_row t_board 2 |> Int64.to_int) +.
    monotonicity_table.(get_row t_board 3 |> Int64.to_int)
  in
  
  -. (row_score +. col_score)

(* Fast smoothness score using lookup tables and inter-row calculations *)
let smoothness_score board =
  (* Horizontal smoothness from lookup table *)
  let horiz_score = 
    smoothness_table.(get_row board 0 |> Int64.to_int) +.
    smoothness_table.(get_row board 1 |> Int64.to_int) +.
    smoothness_table.(get_row board 2 |> Int64.to_int) +.
    smoothness_table.(get_row board 3 |> Int64.to_int)
  in
  
  (* Vertical smoothness - need to check between rows *)
  let vert_score = ref 0.0 in
  for col = 0 to 3 do
    for row = 0 to 2 do
      let value = get_cell board (row * 4 + col) in
      let down = get_cell board ((row + 1) * 4 + col) in
      if value <> 0 && down <> 0 then
        vert_score := !vert_score -. abs_float (float_of_int value -. float_of_int down)
    done
  done;
  
  horiz_score +. !vert_score

let () = init_tables ()