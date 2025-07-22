type random_event = { position : int; value : int; }
type random_tape = { events : random_event array; mutable index : int; }
val load_random_tape : string -> random_tape
val save_random_tape : string -> random_tape -> unit
val get_next_event : random_tape -> random_event
val reset_tape : random_tape -> unit
val create_empty_tape : unit -> random_tape
val record_event : random_tape -> int -> int -> random_tape
val add_random_tile_from_tape : int64 -> random_tape -> int64
val add_tile_with_event : int64 -> random_event -> int64
