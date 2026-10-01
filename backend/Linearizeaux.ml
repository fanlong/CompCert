(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

open LTL
open Maps
open Camlcoq

(* Trivial enumeration, in decreasing order of PC *)

(***
let enumerate_aux f reach =
  positive_rec
    Coq_nil
    (fun pc nodes ->
      if PMap.get pc reach
      then Coq_cons (pc, nodes)
      else nodes)
    f.fn_nextpc
***)

(* More clever enumeration that flattens basic blocks *)

module IntSet = Set.Make(struct type t = int let compare = compare end)

(* Determine join points: reachable nodes that have > 1 predecessor *)

let join_points f =
  let reached = ref IntSet.empty in
  let reached_twice = ref IntSet.empty in
  let rec traverse pc =
    let npc = P.to_int pc in
    if IntSet.mem npc !reached then begin
      if not (IntSet.mem npc !reached_twice) then
        reached_twice := IntSet.add npc !reached_twice
    end else begin
      reached := IntSet.add npc !reached;
      match PTree.get pc f.fn_code with
      | None -> ()
      | Some b -> traverse_succs (successors_block b)
    end
  and traverse_succs = function
    | [] -> ()
    | [pc] -> traverse pc
    | pc :: l -> traverse pc; traverse_succs l
  in traverse f.fn_entrypoint; !reached_twice

(* Cut into reachable basic blocks, annotated with the min value of the PC *)

let basic_blocks f joins =
  let blocks = ref [] in
  let visited = ref IntSet.empty in
  (* start_block:
       pc is the function entry point
          or a join point
          or the successor of a conditional test *)
  let rec start_block pc =
    let npc = P.to_int pc in
    if not (IntSet.mem npc !visited) then begin
      visited := IntSet.add npc !visited;
      in_block [] max_int pc
    end
  (* in_block: add pc to block and check successors *)
  and in_block blk minpc pc =
    let npc = P.to_int pc in
    let blk = pc :: blk in
    let minpc = min npc minpc in
    match PTree.get pc f.fn_code with
    | None -> assert false
    | Some b ->
       let rec do_instr_list = function
       | [] -> assert false
       | Lbranch s :: _ -> next_in_block blk minpc s
       | Ltailcall (sig0, ros) :: _ -> end_block blk minpc
       | Lcond (cond, args, ifso, ifnot) :: _ ->
             end_block blk minpc; start_block ifso; start_block ifnot
       | Ljumptable(arg, tbl) :: _ ->
             end_block blk minpc; List.iter start_block tbl
       | Lreturn :: _ -> end_block blk minpc
       | instr :: b' -> do_instr_list b' in
       do_instr_list b
  (* next_in_block: check if join point and either extend block
     or start block *)
  and next_in_block blk minpc pc =
    let npc = P.to_int pc in
    if IntSet.mem npc joins
    then (end_block blk minpc; start_block pc)
    else in_block blk minpc pc
  (* end_block: record block that we just discovered *)
  and end_block blk minpc =
    blocks := (minpc, List.rev blk) :: !blocks
  in
    start_block f.fn_entrypoint; !blocks

(* Flatten basic blocks in decreasing order of minpc *)

let flatten_blocks blks =
  let cmp_minpc (mpc1, _) (mpc2, _) =
    if mpc1 = mpc2 then 0 else if mpc1 > mpc2 then -1 else 1
  in
    List.flatten (List.map snd (List.sort cmp_minpc blks))

(* Build the enumeration *)

let chain_blocks function_definition block_list =
  let blocks = Array.of_list
    (List.sort (fun (left, _) (right, _) -> compare right left) block_list) in
  let count = Array.length blocks in
  let entries = Hashtbl.create count in
  Array.iteri (fun index (_, nodes) ->
    Hashtbl.add entries (P.to_int (List.hd nodes)) index) blocks;
  let entry = Hashtbl.find entries (P.to_int function_definition.fn_entrypoint) in
  let loop_depths = Loopinfo.depths
    (PTree.map (fun _ block -> successors_block block) function_definition.fn_code)
    function_definition.fn_entrypoint in
  let endings = Array.map (fun (_, nodes) -> List.hd (List.rev nodes)) blocks in
  let depths = Array.map (fun node ->
    match PTree.get node loop_depths with Some depth -> depth | None -> 0) endings in
  let rec fallthrough_targets = function
    | [] -> []
    | Lbranch target :: _ -> [target]
    | Lcond (_, _, taken, other) :: _ -> [taken; other]
    | Ljumptable _ :: _ | Lreturn :: _ | Ltailcall _ :: _ -> []
    | _ :: rest -> fallthrough_targets rest in
  let edges = ref [] in
  Array.iteri (fun source node ->
    let targets =
      match PTree.get node function_definition.fn_code with
      | None -> []
      | Some block -> List.filter_map
          (fun target -> Hashtbl.find_opt entries (P.to_int target))
          (fallthrough_targets block) in
    let high = List.fold_left (fun depth target -> max depth depths.(target)) 0 targets in
    let low = List.fold_left (fun depth target -> min depth depths.(target)) max_int targets in
    List.iter (fun target ->
      let probability =
        if List.length targets = 1 then 100
        else if high > low then (if depths.(target) = high then 90 else 10)
        else if List.mem (source + 1) targets then (if target = source + 1 then 60 else 40)
        else 50 in
      let score = Loopinfo.weight depths.(source) * probability in
      edges := (score, source, target) :: !edges) targets) endings;
  let compare_edges (left_score, left_source, left_target)
                    (right_score, right_source, right_target) =
    let by_score = compare right_score left_score in
    if by_score <> 0 then by_score else
    let by_distance = compare (abs (left_target - left_source))
                              (abs (right_target - right_source)) in
    if by_distance <> 0 then by_distance else
    compare (left_source, left_target) (right_source, right_target) in
  let parents = Array.init count (fun index -> index) in
  let heads = Array.copy parents and tails = Array.copy parents in
  let positions = Array.copy parents and following = Array.make count (-1) in
  let rec representative index =
    if parents.(index) = index then index else begin
      let ancestor = representative parents.(index) in
      parents.(index) <- ancestor;
      ancestor
    end in
  List.iter (fun (_, source, target) ->
    let source_chain = representative source and target_chain = representative target in
    if source_chain <> target_chain && tails.(source_chain) = source
       && heads.(target_chain) = target && target <> entry then begin
      following.(source) <- target;
      parents.(target_chain) <- source_chain;
      tails.(source_chain) <- tails.(target_chain);
      positions.(source_chain) <- min positions.(source_chain) positions.(target_chain)
    end) (List.sort compare_edges !edges);
  let entry_chain = representative entry in
  let chains = List.filter (fun index -> representative index = index)
    (List.init count (fun index -> index)) in
  let compare_chains left right =
    if left = right then 0
    else if left = entry_chain then -1
    else if right = entry_chain then 1
    else compare positions.(left) positions.(right) in
  let enumeration = ref [] in
  List.iter (fun chain ->
    let current = ref heads.(chain) in
    while !current >= 0 do
      enumeration := List.rev_append (snd blocks.(!current)) !enumeration;
      current := following.(!current)
    done) (List.sort compare_chains chains);
  List.rev !enumeration

let enumerate_aux f reach =
  chain_blocks f (basic_blocks f (join_points f))
