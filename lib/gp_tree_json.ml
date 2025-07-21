(* JSON serialization for GP trees *)

open Gp_tree

let node_to_string = function
  | Add -> "ADD"
  | Sub -> "SUB"
  | Mul -> "MUL"
  | SafeDiv -> "SAFEDIV"
  | IfLTE -> "IFLTE"
  | Constant v -> Printf.sprintf "CONST_%.2f" v
  | NumEmptyCells -> "EMPTY"
  | MaxTileValue -> "MAXTILE"
  | MonotonicityScore -> "MONO"
  | SmoothnessScore -> "SMOOTH"

let string_to_node s =
  match s with
  | "ADD" -> Add
  | "SUB" -> Sub
  | "MUL" -> Mul
  | "SAFEDIV" -> SafeDiv
  | "IFLTE" -> IfLTE
  | "EMPTY" -> NumEmptyCells
  | "MAXTILE" -> MaxTileValue
  | "MONO" -> MonotonicityScore
  | "SMOOTH" -> SmoothnessScore
  | s when String.sub s 0 6 = "CONST_" ->
    let v = float_of_string (String.sub s 6 (String.length s - 6)) in
    Constant v
  | _ -> failwith ("Unknown node: " ^ s)

let program_to_json program =
  let nodes_json = program.nodes
    |> Array.to_list
    |> List.map node_to_string
    |> List.map (fun s -> "\"" ^ s ^ "\"")
    |> String.concat ", "
  in
  Printf.sprintf {|{
  "nodes": [%s],
  "fitness": %.2f,
  "games_played": %d,
  "avg_score": %.2f,
  "avg_max_tile": %.2f
}|} nodes_json program.fitness program.games_played program.avg_score program.avg_max_tile

let save_program_to_file program filename =
  let oc = open_out filename in
  output_string oc (program_to_json program);
  close_out oc

let load_program_from_json json_str =
  (* Simple JSON parsing - assumes well-formed input *)
  let extract_array str =
    let start = String.index str '[' in
    let finish = String.index str ']' in
    String.sub str (start + 1) (finish - start - 1)
  in
  
  (* Parse nodes array *)
  let nodes_str = extract_array json_str in
  let node_strings = 
    nodes_str
    |> String.split_on_char ','
    |> List.map String.trim
    |> List.map (fun s -> String.sub s 1 (String.length s - 2)) (* Remove quotes *)
  in
  
  let nodes = node_strings |> List.map string_to_node |> Array.of_list in
  
  {
    nodes = nodes;
    fitness = 0.0;  (* These will be set from the JSON if needed *)
    games_played = 0;
    avg_score = 0.0;
    avg_max_tile = 0.0;
  }

let load_program_from_file filename =
  let ic = open_in filename in
  let json_str = really_input_string ic (in_channel_length ic) in
  close_in ic;
  load_program_from_json json_str