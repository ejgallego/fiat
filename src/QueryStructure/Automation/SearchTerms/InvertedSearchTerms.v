Require Import
        Coq.Strings.String
        ADTSynthesis.QueryStructure.Specification.Representation.QueryStructureNotations
        ADTSynthesis.QueryStructure.Specification.SearchTerms.ListInclusion
        ADTSynthesis.QueryStructure.Implementation.DataStructures.BagADT.IndexSearchTerms
        ADTSynthesis.QueryStructure.Automation.IndexSelection.

(* Instances for building indexes with make simple indexes. *)
(* Every Kind of index is keyed on an inductive type with a single constructor*)
Open Scope string.
Definition InclusionIndex : string := "InclusionIndex".

(* This is our search term type. *)
Record InvertedSearchTerm
       (heading : Heading)
  :=
    { IndexSearchTerm : list string;
      ItemSearchTerm : @Tuple heading -> bool }.

(* This builds the type of searchterms and the matching function on them *)
Global Instance InvertedIndexDenotation
       (heading : Heading)
       (index : @Attributes heading)
       (projection : @Tuple heading -> list string)
: @IndexDenotation "InclusionIndex" heading index :=
  {| DenoteIndex := InvertedSearchTerm heading; (* Pick search term type *)
     MatchIndex search_term item := (* matching function : DenoteIndex -> Tuple heading -> bool *)
       if IncludedIn_dec (IndexSearchTerm search_term) (projection item) then
         ItemSearchTerm search_term item
       else false |}.

(* Extra type class magic for inverted indices. *)
Hint Extern 10 (@IndexDenotation "InclusionIndex" ?heading ?index) =>
let index_domain := eval hnf in (@Domain heading index) in
match index_domain with
  | list string =>
    apply (@InvertedIndexDenotation
             heading index
             (fun tup => GetAttribute tup index ))
end
: typeclass_instances.

(* Tactic for associating IncludedIn clauses with InclusionIndex-es*)
Ltac matchInclusion WhereClause k :=
  match WhereClause with
    | fun tups => IncludedIn _ (@?C1 tups) =>
      let attrs1 := TermAttributes C1 in
      k (map (fun a12 => (InclusionIndex, (fst a12, snd a12)))
             (attrs1))
  end.
