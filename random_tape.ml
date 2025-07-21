(* External random number tape for deterministic game replay *)

type random_event = {
  position: int;  (* 0-15 for board position *)
  value: int;     (* 1 for 2, 2 for 4 *)
}

type random_tape = {
  events: random_event array;
  mutable index: int;
}

let load_random_tape filename =
  let ic = open_in filename in
  let events = ref [] in
  try
    while true do
      let line = input_line ic in
      (* Skip comments and empty lines *)
      if String.length line > 0 && line.[0] <> '#' then begin
        let parts = String.split_on_char ' ' line in
        match List.filter (fun s -> String.length s > 0) parts with
        | [pos; value] ->
          let position = int_of_string pos in
          let value = int_of_string value in
          events := { position; value } :: !events
        | _ -> ()
      end
    done;
    { events = [||]; index = 0 }  (* Never reached *)
  with End_of_file ->
    close_in ic;
    { events = Array.of_list (List.rev !events); index = 0 }

let save_random_tape filename tape =
  let oc = open_out filename in
  Printf.fprintf oc "# Random tape for 2048 game\n";
  Printf.fprintf oc "# Format: position value\n";
  Printf.fprintf oc "# position: 0-15 (board cell index)\n";
  Printf.fprintf oc "# value: 1=2, 2=4\n\n";
  Array.iter (fun event ->
    Printf.fprintf oc "%d %d\n" event.position event.value
  ) tape.events;
  close_out oc

let get_next_event tape =
  if tape.index >= Array.length tape.events then
    failwith "Random tape exhausted"
  else begin
    let event = tape.events.(tape.index) in
    tape.index <- tape.index + 1;
    event
  end

let reset_tape tape =
  tape.index <- 0

let create_empty_tape () =
  { events = [||]; index = 0 }

let record_event tape position value =
  let event = { position; value } in
  let new_events = Array.append tape.events [|event|] in
  { tape with events = new_events }

(* Modified add_random_tile that uses external tape *)
let add_random_tile_from_tape board tape =
  let open Game in
  let empty_cells = get_empty_cells board in
  match empty_cells with
  | [] -> board
  | cells ->
    let event = get_next_event tape in
    (* Map tape position to actual empty cell index *)
    let actual_idx = 
      if event.position < List.length cells then
        List.nth cells event.position
      else
        List.nth cells (event.position mod List.length cells)
    in
    set_cell board actual_idx event.value