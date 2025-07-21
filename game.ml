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

let left_table = Array.make 65536 0
let right_table = Array.make 65536 0
let score_table = Array.make 65536 0

let init_tables () =
  for row = 0 to 65535 do
    let cells = Array.init 4 (fun i -> (row lsr (i * 4)) land 0xF) in
    
    (* Compute left move *)
    let left_cells = Array.copy cells in
    let write_pos = ref 0 in
    let score = ref 0 in
    
    for read_pos = 0 to 3 do
      if left_cells.(read_pos) <> 0 then begin
        if !write_pos > 0 && left_cells.(!write_pos - 1) = left_cells.(read_pos) then begin
          left_cells.(!write_pos - 1) <- left_cells.(!write_pos - 1) + 1;
          score := !score + (1 lsl left_cells.(!write_pos - 1));
          left_cells.(read_pos) <- 0
        end else begin
          if !write_pos <> read_pos then begin
            left_cells.(!write_pos) <- left_cells.(read_pos);
            left_cells.(read_pos) <- 0
          end;
          write_pos := !write_pos + 1
        end
      end
    done;
    
    let left_result = ref 0 in
    for i = 0 to 3 do
      left_result := !left_result lor (left_cells.(i) lsl (i * 4))
    done;
    left_table.(row) <- !left_result;
    score_table.(row) <- !score;
    
    (* Compute right move by reversing *)
    let right_cells = Array.init 4 (fun i -> cells.(3 - i)) in
    let write_pos = ref 0 in
    
    for read_pos = 0 to 3 do
      if right_cells.(read_pos) <> 0 then begin
        if !write_pos > 0 && right_cells.(!write_pos - 1) = right_cells.(read_pos) then begin
          right_cells.(!write_pos - 1) <- right_cells.(!write_pos - 1) + 1;
          right_cells.(read_pos) <- 0
        end else begin
          if !write_pos <> read_pos then begin
            right_cells.(!write_pos) <- right_cells.(read_pos);
            right_cells.(read_pos) <- 0
          end;
          write_pos := !write_pos + 1
        end
      end
    done;
    
    let right_result = ref 0 in
    for i = 0 to 3 do
      right_result := !right_result lor (right_cells.(3 - i) lsl (i * 4))
    done;
    right_table.(row) <- !right_result
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

let monotonicity_score board =
  let score = ref 0.0 in
  
  (* Check rows *)
  for row = 0 to 3 do
    let row_vals = Array.init 4 (fun col -> get_cell board (row * 4 + col)) in
    let inc = ref 0.0 in
    let dec = ref 0.0 in
    for i = 0 to 2 do
      if row_vals.(i) > row_vals.(i + 1) then
        dec := !dec +. float_of_int (row_vals.(i) - row_vals.(i + 1))
      else if row_vals.(i) < row_vals.(i + 1) then
        inc := !inc +. float_of_int (row_vals.(i + 1) - row_vals.(i))
    done;
    score := !score +. Stdlib.max !inc !dec
  done;
  
  (* Check columns *)
  for col = 0 to 3 do
    let col_vals = Array.init 4 (fun row -> get_cell board (row * 4 + col)) in
    let inc = ref 0.0 in
    let dec = ref 0.0 in
    for i = 0 to 2 do
      if col_vals.(i) > col_vals.(i + 1) then
        dec := !dec +. float_of_int (col_vals.(i) - col_vals.(i + 1))
      else if col_vals.(i) < col_vals.(i + 1) then
        inc := !inc +. float_of_int (col_vals.(i + 1) - col_vals.(i))
    done;
    score := !score +. Stdlib.max !inc !dec
  done;
  
  -. !score

let smoothness_score board =
  let score = ref 0.0 in
  
  for row = 0 to 3 do
    for col = 0 to 3 do
      let value = get_cell board (row * 4 + col) in
      if value <> 0 then begin
        (* Check right neighbor *)
        if col < 3 then begin
          let right = get_cell board (row * 4 + col + 1) in
          if right <> 0 then
            score := !score -. abs_float (float_of_int value -. float_of_int right)
        end;
        (* Check down neighbor *)
        if row < 3 then begin
          let down = get_cell board ((row + 1) * 4 + col) in
          if down <> 0 then
            score := !score -. abs_float (float_of_int value -. float_of_int down)
        end
      end
    done
  done;
  
  !score

let () = init_tables ()