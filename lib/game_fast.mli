type board = int64
val empty_board : int64
val row_mask : int64
val cell_mask : int64
val get_row : int64 -> int -> int64
val set_row : int64 -> int -> int64 -> int64
val get_cell : int64 -> int -> int
val set_cell : int64 -> int -> int -> int64
val left_table : int array
val right_table : int array
val score_table : int array
val monotonicity_table : float array
val smoothness_table : float array
val load_table_from_file : string -> int array
val compute_row_monotonicity : int -> float
val compute_row_smoothness : int -> float
val init_tables : unit -> unit
val transpose : int64 -> int64
val move_left : int64 -> int64
val move_right : int64 -> int64
val move_up : int64 -> int64
val move_down : int64 -> int64
val get_score_for_move : int64 -> [< `Down | `Left | `Right | `Up ] -> int
val count_empty_cells : int64 -> int
val get_empty_cells : int64 -> int list
val add_random_tile : int64 -> Random.State.t -> int64
val get_max_tile : int64 -> int
val is_game_over : Int64.t -> bool
val monotonicity_score : int64 -> float
val smoothness_score : int64 -> float
