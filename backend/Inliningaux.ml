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

open AST
open Datatypes
open FSetAVL
open Maps
open Op
open Ordered
open! RTL

module PSet = Make(OrderedPositive)

type inlining_info = {
  call_cnt : int PTree.t; (* Count the number of direct calls to a function *)
  addr_taken : PSet.t; (* The set of globals which have their address taken *)
  calls_out : PSet.t; (* Functions that make at least one direct call *)
}

let empty_inlining_info = {
  call_cnt = PTree.empty;
  addr_taken = PSet.empty;
  calls_out = PSet.empty;
}

let call_count id io =
  match PTree.get id io.call_cnt with
  | Some cnt -> cnt
  | None -> 0

let called id io =
  let call_cnt = PTree.set id (1 + call_count id io) io.call_cnt in
  { io with call_cnt = call_cnt }

let address_taken id io =
  PSet.mem id io.addr_taken

let rec used_id io ids =
  match ids with
  | [] -> io
  | id::ids ->
     used_id {io with addr_taken = PSet.add id io.addr_taken} ids

let used_in_globvar io gv =
  let used_in_init_data io = function
    | Init_addrof (id,_) -> used_id io [id]
    | _ -> io in
  List.fold_left used_in_init_data io gv.gvar_init

let fun_inline_analysis id io fn =
  let inst io nid = function
    | Iop (op, args, dest, succ) -> used_id io (globals_operation op)
    | Iload (chunk, addr, args, dest, succ)
    | Istore (chunk, addr, args, dest, succ) -> used_id io (globals_addressing addr)
    | Ibuiltin (ef, args, dest, succ) -> used_id io (globals_of_builtin_args args)
    | Icall (_, Coq_inr cid, _, _, _)
    | Itailcall (_, Coq_inr cid, _) ->
        called cid { io with calls_out = PSet.add id io.calls_out }
    | _ -> io in
  PTree.fold inst fn.fn_code io

(* Gather information about the program used for inlining heuristic *)
let inlining_analysis (p: program) =
  if !Clflags.option_finline then
    List.fold_left (fun io idg ->
        match idg with
        | fid, Gfun (Internal f) -> fun_inline_analysis fid io f
        | _, Gvar gv -> used_in_globvar io gv
        | _ -> io) empty_inlining_info p.prog_defs
  else
    empty_inlining_info

(* Test whether a function is static and called only once *)
let static_called_once id io =
  if !Clflags.option_finline_functions_called_once then
    C2C.atom_is_static id && call_count id io <= 1 && not (address_taken id io)
  else
    false

(* Tiny static wrappers used by a bounded number of callers generally benefit
   from eliminating call/return and argument moves without meaningful code
   growth.  The inlining correctness proof is independent of this heuristic. *)

let repeated_inline_call_limit = 8
let repeated_inline_node_limit = 32
let leaf_repeated_call_limit = 12
let leaf_repeated_node_limit = 16

let static_small_repeated id io f =
  let calls = call_count id io in
  let nodes = PTree.fold (fun count _ _ -> count + 1) f.fn_code 0 in
  C2C.atom_is_static id && calls > 1 && not (address_taken id io)
  && ((calls <= repeated_inline_call_limit && nodes <= repeated_inline_node_limit)
      || (calls <= leaf_repeated_call_limit && nodes <= leaf_repeated_node_limit
          && not (PSet.mem id io.calls_out)))

let should_inline (io: inlining_info) (id: ident) (f: coq_function) =
  if !Clflags.option_finline then begin
    match C2C.atom_inline id with
    | C2C.Inline -> true
    | C2C.Noinline -> false
    | C2C.No_specifier ->
        static_called_once id io || static_small_repeated id io f
  end else
    false
