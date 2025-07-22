type node =
  | Add
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
  nodes: node array;
  mutable fitness: float;
  mutable games_played: int;
  mutable avg_score: float;
  mutable avg_max_tile: float;
}

let node_arity = function
  | Add | Sub | Mul | SafeDiv -> 2
  | IfLTE -> 4
  | Constant _ | NumEmptyCells | MaxTileValue 
  | MonotonicityScore | SmoothnessScore -> 0

let is_terminal = function
  | Constant _ | NumEmptyCells | MaxTileValue 
  | MonotonicityScore | SmoothnessScore -> true
  | _ -> false

let safe_div a b =
  if abs_float b < 0.001 then 1.0 else a /. b

let eval_program program board =
  let open Game_fast in
  let rec eval_node idx =
    if idx >= Array.length program.nodes then
      (0.0, idx)
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
        (float_of_int (count_empty_cells board), idx + 1)
      | MaxTileValue ->
        (* Return log2 value to match Python *)
        let max_log2 = ref 0 in
        for i = 0 to 15 do
          let cell = get_cell board i in
          if cell > !max_log2 then max_log2 := cell
        done;
        (float_of_int !max_log2, idx + 1)
      | MonotonicityScore ->
        (monotonicity_score board, idx + 1)
      | SmoothnessScore ->
        (smoothness_score board, idx + 1)
  in
  let result, _ = eval_node 0 in
  result

let eval program board = eval_program program board

let random_terminal rng =
  match Random.State.int rng 5 with
  | 0 -> Constant (Random.State.float rng 2.0 -. 1.0)
  | 1 -> NumEmptyCells
  | 2 -> MaxTileValue
  | 3 -> MonotonicityScore
  | _ -> SmoothnessScore

let random_function rng =
  match Random.State.int rng 5 with
  | 0 -> Add
  | 1 -> Sub
  | 2 -> Mul
  | 3 -> SafeDiv
  | _ -> IfLTE

let rec random_tree rng max_depth =
  if max_depth <= 1 || Random.State.float rng 1.0 < 0.3 then
    [random_terminal rng]
  else
    let func = random_function rng in
    let arity = node_arity func in
    let subtrees = List.init arity (fun _ -> random_tree rng (max_depth - 1)) in
    func :: List.flatten subtrees

let create_random_program rng max_depth =
  let nodes = random_tree rng max_depth |> Array.of_list in
  { nodes; fitness = 0.0; games_played = 0; avg_score = 0.0; avg_max_tile = 0.0 }

let copy_program program =
  { nodes = Array.copy program.nodes;
    fitness = program.fitness;
    games_played = program.games_played;
    avg_score = program.avg_score;
    avg_max_tile = program.avg_max_tile }

let count_nodes_from idx nodes =
  let rec count idx =
    if idx >= Array.length nodes then (0, idx)
    else
      let arity = node_arity nodes.(idx) in
      let rec count_children idx remaining acc =
        if remaining = 0 then (acc, idx)
        else
          let child_count, next_idx = count idx in
          count_children next_idx (remaining - 1) (acc + child_count)
      in
      let children_count, next_idx = count_children (idx + 1) arity 0 in
      (1 + children_count, next_idx)
  in
  let total, _ = count idx in
  total

let extract_subtree nodes start_idx =
  let size = count_nodes_from start_idx nodes in
  Array.sub nodes start_idx size

let crossover rng parent1 parent2 =
  let child1 = copy_program parent1 in
  let child2 = copy_program parent2 in
  
  let find_random_subtree_idx nodes =
    let total_nodes = Array.length nodes in
    if total_nodes <= 1 then 0
    else
      let idx = ref 0 in
      let attempts = ref 0 in
      while !attempts < 10 do
        idx := Random.State.int rng total_nodes;
        if !idx + count_nodes_from !idx nodes <= total_nodes then
          attempts := 10
        else
          incr attempts
      done;
      !idx
  in
  
  let idx1 = find_random_subtree_idx child1.nodes in
  let idx2 = find_random_subtree_idx child2.nodes in
  
  let subtree1 = extract_subtree child1.nodes idx1 in
  let subtree2 = extract_subtree child2.nodes idx2 in
  
  let size1 = Array.length subtree1 in
  let size2 = Array.length subtree2 in
  
  let replace_subtree nodes idx old_size new_subtree =
    let prefix = Array.sub nodes 0 idx in
    let suffix_start = idx + old_size in
    let suffix_len = Array.length nodes - suffix_start in
    let suffix = if suffix_len > 0 then Array.sub nodes suffix_start suffix_len else [||] in
    Array.concat [prefix; new_subtree; suffix]
  in
  
  let new_nodes1 = replace_subtree child1.nodes idx1 size1 subtree2 in
  let new_nodes2 = replace_subtree child2.nodes idx2 size2 subtree1 in
  let child1 = { child1 with nodes = new_nodes1 } in
  let child2 = { child2 with nodes = new_nodes2 } in
  
  child1.fitness <- 0.0;
  child1.games_played <- 0;
  child2.fitness <- 0.0;
  child2.games_played <- 0;
  
  (child1, child2)

let mutate rng program mutation_rate max_depth =
  if Random.State.float rng 1.0 < mutation_rate then begin
    let child = copy_program program in
    let idx = Random.State.int rng (Array.length child.nodes) in
    let old_size = count_nodes_from idx child.nodes in
    let new_subtree = random_tree rng max_depth |> Array.of_list in
    
    let prefix = Array.sub child.nodes 0 idx in
    let suffix_start = idx + old_size in
    let suffix_len = Array.length child.nodes - suffix_start in
    let suffix = if suffix_len > 0 then Array.sub child.nodes suffix_start suffix_len else [||] in
    
    let new_nodes = Array.concat [prefix; new_subtree; suffix] in
    let child = { child with nodes = new_nodes } in
    child.fitness <- 0.0;
    child.games_played <- 0;
    child
  end else
    program

let program_to_string program =
  let node_to_string = function
    | Add -> "Add"
    | Sub -> "Sub"
    | Mul -> "Mul"
    | SafeDiv -> "SafeDiv"
    | IfLTE -> "IfLTE"
    | Constant c -> Printf.sprintf "Constant(%.6f)" c
    | NumEmptyCells -> "NumEmptyCells"
    | MaxTileValue -> "MaxTileValue"
    | MonotonicityScore -> "MonotonicityScore"
    | SmoothnessScore -> "SmoothnessScore"
  in
  let nodes_str = Array.map node_to_string program.nodes |> Array.to_list |> String.concat ", " in
  Printf.sprintf "[%s]" nodes_str
