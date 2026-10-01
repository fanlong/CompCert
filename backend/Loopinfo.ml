open Camlcoq
open Maps

let depths successors entrypoint =
  let visited = Hashtbl.create 127 in
  let order = ref [] in
  let pending = ref [entrypoint, false] in
  while !pending <> [] do
    match !pending with
    | [] -> ()
    | (node, finished) :: rest ->
        pending := rest;
        if finished then order := node :: !order
        else if not (Hashtbl.mem visited (P.to_int node)) then begin
          Hashtbl.add visited (P.to_int node) ();
          let targets =
            match PTree.get node successors with
            | None -> []
            | Some targets -> targets in
          pending := List.fold_right
            (fun target stack -> (target, false) :: stack)
            targets ((node, true) :: !pending)
        end
  done;
  let nodes = Array.of_list !order in
  let count = Array.length nodes in
  let ranks = Hashtbl.create count in
  Array.iteri (fun index node -> Hashtbl.add ranks (P.to_int node) index) nodes;
  let edges = Array.map
    (fun node ->
      match PTree.get node successors with
      | None -> []
      | Some targets -> List.filter_map
          (fun target -> Hashtbl.find_opt ranks (P.to_int target)) targets)
    nodes in
  let predecessors = Array.make count [] in
  Array.iteri (fun source targets -> List.iter
    (fun target -> predecessors.(target) <- source :: predecessors.(target)) targets)
    edges;
  let dominators = Array.make count (-1) in
  dominators.(0) <- 0;
  let intersect first second =
    let left = ref first and right = ref second in
    while !left <> !right do
      if !left > !right then left := dominators.(!left)
      else right := dominators.(!right)
    done;
    !left in
  let changed = ref true in
  while !changed do
    changed := false;
    for index = 1 to count - 1 do
      let known = List.filter (fun pred -> dominators.(pred) >= 0) predecessors.(index) in
      match known with
      | [] -> ()
      | first :: rest ->
          let parent = List.fold_left intersect first rest in
          if dominators.(index) <> parent then begin
            dominators.(index) <- parent;
            changed := true
          end
    done
  done;
  let children = Array.make count [] in
  for index = 1 to count - 1 do
    let parent = dominators.(index) in
    children.(parent) <- index :: children.(parent)
  done;
  let starts = Array.make count 0 and ends = Array.make count 0 in
  let sequence = ref 0 and traversal = ref [0, false] in
  while !traversal <> [] do
    match !traversal with
    | [] -> ()
    | (index, finished) :: rest ->
        traversal := rest;
        if finished then ends.(index) <- !sequence
        else begin
          starts.(index) <- !sequence;
          incr sequence;
          traversal := List.fold_right
            (fun child stack -> (child, false) :: stack)
            children.(index) ((index, true) :: !traversal)
        end
  done;
  let latches = Array.make count [] in
  Array.iteri (fun source targets -> List.iter
    (fun target ->
      if starts.(target) <= starts.(source) && starts.(source) < ends.(target)
      then latches.(target) <- source :: latches.(target)) targets) edges;
  let nesting = Array.make count 0 and marks = Array.make count (-1) in
  Array.iteri (fun header sources ->
    if sources <> [] then begin
      marks.(header) <- header;
      nesting.(header) <- min 6 (nesting.(header) + 1);
      let work = ref sources in
      while !work <> [] do
        match !work with
        | [] -> ()
        | index :: rest ->
            work := rest;
            if marks.(index) <> header then begin
              marks.(index) <- header;
              nesting.(index) <- min 6 (nesting.(index) + 1);
              work := List.rev_append predecessors.(index) !work
            end
      done
    end) latches;
  let result = ref PTree.empty in
  Array.iteri (fun index node -> result := PTree.set node nesting.(index) !result) nodes;
  !result

let weight depth =
  let result = ref 1 in
  for _level = 1 to min 6 depth do
    result := !result * 8
  done;
  !result
