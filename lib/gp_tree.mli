type node =
    Add
  | Sub
  | Mul
  | SafeDiv
  | IfLTE
  | Constant of float
  | NumEmptyCells
  | MaxTileValue
  | MonotonicityScore
  | SmoothnessScore
type program = {
  nodes : node array;
  mutable fitness : float;
  mutable games_played : int;
  mutable avg_score : float;
  mutable avg_max_tile : float;
}
val node_arity : node -> int
val is_terminal : node -> bool
val safe_div : float -> float -> float
val eval_program : program -> int64 -> float
val eval : program -> int64 -> float
val random_terminal : Random.State.t -> node
val random_function : Random.State.t -> node
val random_tree : Random.State.t -> int -> node list
val create_random_program : Random.State.t -> int -> program
val copy_program : program -> program
val count_nodes_from : int -> node array -> int
val extract_subtree : node array -> int -> node array
val crossover : Random.State.t -> program -> program -> program * program
val mutate : Random.State.t -> program -> float -> int -> program
val program_to_string : program -> string
