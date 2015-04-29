(** * Well-founded relation on [reachable] *)
Require Import Coq.Strings.String Coq.Lists.List Coq.Program.Program Coq.Program.Wf Coq.Arith.Wf_nat Coq.Relations.Relation_Definitions.
Require Import Fiat.Parsers.ContextFreeGrammar Fiat.Parsers.Reachable.AllReachable.
Require Import Fiat.Parsers.BaseTypes.

Section rel.
  Context {Char} {HSL : StringLike Char} {predata : parser_computational_predataT} {G : grammar Char}.

  Section size.
    Context {ch : Char}.
    Definition size_of_reachable_from_item'
               (size_of_reachable_from_productions : forall {pats}, reachable_from_productions G ch pats -> nat)
               {it} (p : reachable_from_item G ch it) : nat
      := match p with
           | ReachableTerminal => 0
           | ReachableNonTerminal _ _ p' => S (size_of_reachable_from_productions p')
         end.

    Fixpoint size_of_reachable_from_productions {pats} (p : reachable_from_productions G ch pats) : nat
      := match p with
           | ReachableHead _ _ p' => S (size_of_reachable_from_production p')
           | ReachableTail _ _ p' => S (size_of_reachable_from_productions p')
         end
    with size_of_reachable_from_production {pat} (p : reachable_from_production G ch pat) : nat
         := match p with
              | ReachableProductionHead _ _ p' => S (size_of_reachable_from_item' (@size_of_reachable_from_productions) p')
              | ReachableProductionTail _ _ p' => S (size_of_reachable_from_production p')
            end.

    Definition size_of_reachable_from_item
               {it} (p : reachable_from_item G ch it) : nat
      := @size_of_reachable_from_item' (@size_of_reachable_from_productions) it p.
  End size.
End rel.
