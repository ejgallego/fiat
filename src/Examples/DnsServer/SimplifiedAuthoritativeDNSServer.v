Require Import Coq.Vectors.Vector
        Coq.Strings.Ascii
        Coq.Bool.Bool
        Coq.Lists.List.

Require Import
        Fiat.Common.Tactics.CacheStringConstant
        Fiat.Computation.Decidable
        Fiat.Computation.IfDec
        Fiat.Computation.FoldComp
        Fiat.Computation.FueledFix
        Fiat.Computation.ListComputations
        Fiat.QueryStructure.Automation.Common
        Fiat.QueryStructure.Automation.MasterPlan
        Fiat.QueryStructure.Implementation.DataStructures.BagADT.BagADT
        Fiat.QueryStructure.Automation.IndexSelection
        Fiat.QueryStructure.Specification.SearchTerms.ListPrefix
        Fiat.QueryStructure.Automation.SearchTerms.FindStringPrefixSearchTerms
        Fiat.QueryStructure.Automation.QSImplementation.

Require Import
        Bedrock.Word
        Fiat.BinEncoders.Env.Common.Specs
        Fiat.BinEncoders.Env.BinLib.Core
        Fiat.BinEncoders.Env.Examples.SimpleDnsOpt
        Fiat.BinEncoders.Env.Lib2.DomainNameOpt
        Fiat.BinEncoders.Env.BinLib.AlignedByteString.

Require Import Fiat.Examples.DnsServer.SimplePacket
        Fiat.Examples.DnsServer.DecomposeSumField
        Fiat.Examples.DnsServer.SimpleDnsLemmas
        Fiat.Examples.DnsServer.DnsAutomation
        Fiat.Examples.DnsServer.SimpleAuthoritativeDNSSchema.

Section BinaryDns.

  Variable recurseDepth : nat.
  Variable buffSize : nat.

  Definition DnsSig : ADTSig :=
    ADTsignature {
      Constructor "Init" : rep,
      Method "AddData" : rep * resourceRecord -> rep * bool,
      Method "Process" : rep * (Vector.t (word 8) (12 + buffSize)) -> rep * (option ByteString)
    }.

Definition DnsSpec : ADT DnsSig :=
  Def ADT {
    rep := QueryStructure DnsSchema,

    Def Constructor "Init" : rep := empty,,

    (* in start honing querystructure, it inserts constraints before *)
    (* every insert / decision procedure *)

    Def Method1 "AddData" (this : rep) (t : resourceRecord) : rep * bool :=
      Insert t into this!sRRecords,

    Def Method1 "Process" (this : rep) (b : Vector.t (word 8) (12 + buffSize)) : rep * (option ByteString) :=
        p' <- Pick_Decoder_For DNS_Packet_OK encode_packet_Spec (build_aligned_ByteString b) list_CacheEncode_empty;
       Ifopt p' as p Then
        p' <- Repeat recurseDepth initializing n with (p!"question"!"qname", @nil CNAME_Record)
               defaulting rec with (encode_packet_Spec (buildempty true ``"ServFail" p) list_CacheEncode_empty) (* Bottoming out w/o an answer signifies a server failure error. *)
        {{ results <- MaxElements (fun r r' : resourceRecord => prefix r!sNAME r'!sNAME)
                   (For (r in this!sRRecords)      (* Bind a list of all the DNS entries *)
                               Where (prefix r!sNAME (fst n))   (* prefixed with [n] to [rs] *)
                               Return r);
            If (is_empty results) (* Are there any matching records? *)
            Then encode_packet_Spec (add_answers (map CNAME_Record2RRecord (snd n)) (buildempty true ``"NXDomain" p)) list_CacheEncode_empty(* No matching records, set name error *)
            Else
            (IfDec (List.Forall (fun r : resourceRecord => r!sNAME = (fst n)) results) (* If the record's QNAME is an exact match  *)
              Then
              b <- SingletonSet (fun b : CNAME_Record =>      (* If the record is a CNAME, *)
                                   List.In (A := resourceRecord) b results
                                   /\ p!"question"!"qtype" <> QType_inj CNAME); (* and a non-CNAME was requested*)
                Ifopt b as b'
                Then  (* only one matching CNAME record *)
                  rec (b'!sRDATA, b' :: snd n) (* Recursively find records matching the CNAME, *)
                (* Adding the CNAME RR to the answer section *)
                Else     (* Copy the records with the correct QTYPE into the answer *)
                         (* section of an empty response *)
                (results <- ⟦ element in results | QType_match (RDataTypeToRRecordType element!sRDATA) (p!"question"!"qtype") ⟧;
                  encode_packet_Spec (add_answers (map CNAME_Record2RRecord (snd n)) (add_answers results (buildempty true ``"NoError" p))) list_CacheEncode_empty)
              Else (* prefix but record's QNAME not an exact match *)
                (* return all the prefix records that are nameserver records -- *)
                (* ask the authoritative servers *)
              (ns_results <- { ns_results | forall x : NS_Record, List.In x ns_results <-> List.In (A := resourceRecord) x results };
                 (* Append all the glue records to the additional section. *)
                 glue_results <- (foldComp (fun glue_records (ns_result : NS_Record) =>
                                              glue_records' <- (For (rRec in this!sRRecords)
                                                               Where (rRec!sNAME = ns_result!sRDATA)
                                                               Return rRec);
                                                ret (glue_records' ++ glue_records)) [ ] ns_results);
                 (* Would prefer this, but need to disallow duplicate NS records
                    (which is probably a correct and reasonable constraint) for this to be equivalent.
                 glue_results <- For (rRec in this!sRRecords)
                                 Where (List.In rRec!sNAME (map (fun r : NS_Record => r!sRDATA) ns_results))
                                 Return rRec; *)
                 encode_packet_Spec (add_answers (map CNAME_Record2RRecord (snd n)) (add_additionals glue_results (add_nses (map VariantResourceRecord2RRecord ns_results) (buildempty true ``"NoError" p)))) list_CacheEncode_empty))
        }};
       ret (this, Some (fst p'))
           Else ret (this, None)
           }.

Local Opaque encode_packet_Spec.
Local Opaque packetDecoderImpl.

Local Opaque MaxElements.
Local Opaque encode_packet_Spec.
Local Opaque SumType.SumType_index.
Local Opaque SumType.SumType_proj.

Ltac implement_insert'' :=
  implement_insert' ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
         ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
         ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm)
         ltac:(CombineCase7 StringPrefixIndexUse_dep EqIndexUse_dep)
         ltac:(CombineCase11 createEarlyStringPrefixTerm_dep createEarlyEqualityTerm_dep)
         ltac:(CombineCase8 createLastStringPrefixTerm_dep createLastEqualityTerm_dep).

Ltac drop_constraints :=
  first
    [ simplify with monad laws
    | drop_constraints_from_query'
    | rewrite refine_If_Then_Else_Bind
    | rewrite refine_If_Opt_Then_Else_Bind
    | rewrite refine_if_Then_Else_Duplicate
    | apply refine_MaxElements'
    | eapply refineFueledFix; [
      | let refine_bid := fresh in
        intros ? ? ? refine_bod; repeat setoid_rewrite refine_bod ]
    | implement_DropQSConstraints_AbsR ].


Instance ADomainName_eq : Query_eq DomainName := Astring_eq.
Instance ARRecordType_eq : Query_eq RRecordType :=
  {| A_eq_dec := fin_eq_dec |}.

Lemma refine_decode_packet
  : forall b,
    refine (Pick_Decoder_For DNS_Packet_OK encode_packet_Spec (build_aligned_ByteString b) list_CacheEncode_empty)
           (ret (Ifopt (ByteAligned_packetDecoderImpl' buffSize b list_CacheDecode_empty) as p Then Some (fst (fst p)) Else None)).
Proof.
  intros; setoid_rewrite refine_Pick_Decoder_For with (decoderImpl := packet_decoder); eauto using list_cache_empty_Equiv.
  replace (projT1 packet_decoder) with packetDecoderImpl.
  unfold list_CacheDecode_empty.
  pose proof (ByteAligned_packetDecoderImpl'_OK _ b).
  rewrite <- H.
  unfold If_Opt_Then_Else.
  f_equiv.
  match goal with
    |- context [match ?z with _ => _ end =
                match ?z' with _ => _ end] =>
    replace z with z' by reflexivity; destruct z' as [ [ [? ?] ?] | ];
      reflexivity
  end.
  reflexivity.
  simpl; unfold GoodCache; simpl; intuition; try congruence.
Qed.

Arguments natToWord : simpl never.
  Arguments wordToNat : simpl never.
  Arguments NPeano.div : simpl never.
  Arguments AlignWord.split1' : simpl never.
  Arguments AlignWord.split2' : simpl never.
  Arguments weq : simpl never.
  Arguments EnumOpt.word_indexed : simpl never.
  Arguments Guarded_Vector_split : simpl never.
  Arguments addD : simpl never.
  Arguments Core.append_word : simpl never.
  Arguments Vector_split : simpl never.
  Local Opaque pow2.


Local Opaque CallBagFind.

    Lemma refine_Query_In_Where_False {qs_schema} {ResultT}
      : forall Index
               (r_o : UnConstrQueryStructure qs_schema)
               (r_n : IndexedQueryStructure qs_schema Index)
               idx
               (body : _ -> Comp (list ResultT)),
        DelegateToBag_AbsR r_o r_n
        ->
        refine For (UnConstrQuery_In r_o idx
                          (fun tup : RawTuple =>
                             Where False (body tup) ))
               (ret [ ]).
    Proof.
    Admitted.


    Lemma refine_Query_In_Where_Const {qs_schema} {ResultT} {A}
          {_ : @Query_eq A}
      : forall Index
               (r_o : UnConstrQueryStructure qs_schema)
               (r_n : IndexedQueryStructure qs_schema Index)
               idx
               (body : _ -> Comp (list ResultT))
               Q a a',
        DelegateToBag_AbsR r_o r_n
        -> refine For (UnConstrQuery_In r_o idx
                                     (fun tup : RawTuple =>
                                        Where (a = a' /\ Q tup)
                                              (body tup) ))
               (If A_eq_dec a a' Then
                   For (UnConstrQuery_In r_o idx
                                     (fun tup : RawTuple =>
                                        Where (Q tup)
                                              (body tup) ))
                   Else
                   (ret [ ])).
    Proof.
    Admitted.

    Corollary refine_Count_Query_In_Where_False {qs_schema} {ResultT}
      : forall Index
               (r_o : UnConstrQueryStructure qs_schema)
               (r_n : IndexedQueryStructure qs_schema Index)
               idx
               (body : _ -> Comp (list ResultT)),
        DelegateToBag_AbsR r_o r_n
        ->
        refine (Count For (UnConstrQuery_In r_o idx
                          (fun tup : RawTuple =>
                             Where False (body tup) )))
               (ret 0).
    Proof.
      intros; rewrite refine_Query_In_Where_False; simpl; eauto.
      rewrite refine_Count; simplify with monad laws; reflexivity.
    Qed.

    Corollary refine_Count_Query_In_Where_Const {qs_schema} {ResultT} {A}
          {_ : @Query_eq A}
      : forall Index
               (r_o : UnConstrQueryStructure qs_schema)
               (r_n : IndexedQueryStructure qs_schema Index)
               idx
               (body : _ -> Comp (list ResultT))
               Q a a',
        DelegateToBag_AbsR r_o r_n
        -> refine (Count For (UnConstrQuery_In r_o idx
                                     (fun tup : RawTuple =>
                                        Where (a = a' /\ Q tup)
                                              (body tup) )))
               (If A_eq_dec a a' Then
                   (Count For (UnConstrQuery_In r_o idx
                                     (fun tup : RawTuple =>
                                        Where (Q tup)
                                              (body tup) )))
                   Else
                   (ret 0)).
    Proof.
      intros; rewrite refine_Query_In_Where_Const; eauto.
      find_if_inside; simpl; eauto.
      reflexivity.
      rewrite refine_Count; simplify with monad laws; reflexivity.
    Qed.

    Lemma refine_Query_In_Where_Const_neq {qs_schema} {ResultT} {A}
          {_ : @Query_eq A}
      : forall Index
               (r_o : UnConstrQueryStructure qs_schema)
               (r_n : IndexedQueryStructure qs_schema Index)
               idx
               (body : _ -> Comp (list ResultT))
               Q a a',
        DelegateToBag_AbsR r_o r_n
        -> refine For (UnConstrQuery_In r_o idx
                                     (fun tup : RawTuple =>
                                        Where (a <> a' /\ Q tup)
                                              (body tup) ))
               (If A_eq_dec a a' Then
                   (ret [ ])
                   Else
                   For (UnConstrQuery_In r_o idx
                                         (fun tup : RawTuple =>
                                            Where (Q tup)
                                                  (body tup) ))
).
    Proof.
    Admitted.

    Corollary refine_Count_Query_In_Where_Const_neq {qs_schema} {ResultT} {A}
          {_ : @Query_eq A}
      : forall Index
               (r_o : UnConstrQueryStructure qs_schema)
               (r_n : IndexedQueryStructure qs_schema Index)
               idx
               (body : _ -> Comp (list ResultT))
               Q a a',
        DelegateToBag_AbsR r_o r_n
        -> refine (Count For (UnConstrQuery_In r_o idx
                                     (fun tup : RawTuple =>
                                        Where (a <> a' /\ Q tup)
                                              (body tup) )))
               (If A_eq_dec a a' Then
                   (ret 0)
                   Else
                   (Count For (UnConstrQuery_In r_o idx
                                                (fun tup : RawTuple =>
                                                   Where (Q tup)
                                                         (body tup) )))).
    Proof.
      intros; rewrite refine_Query_In_Where_Const_neq; eauto.
      find_if_inside; simpl; eauto.
      rewrite refine_Count; simplify with monad laws; reflexivity.
      reflexivity.
    Qed.

Lemma refine_MaxPrefix {resultT}
  : forall (f : resultT -> string) (l : Comp (list resultT)),
    refine (MaxElements (fun s s' => prefix (f s) (f s')) l)
           (results <- l;
              ret (snd (@fold_left (prod string (list resultT)) resultT
                                   (fun maxes s => If prefix (fst maxes) (f s) Then
                                                      (If prefix (f s) (fst maxes) Then (fst maxes, s :: (snd maxes))
                                                          Else (f s, [s]))
                                                      Else maxes) results ("", [ ])))).
Proof.
Admitted.

    Ltac implement_Count find_search_term ::=
  match goal with
    [ H : @DelegateToBag_AbsR ?qs_schema ?indices ?r_o ?r_n
      |- refine (Bind (Count For (UnConstrQuery_In _ ?idx (fun tup => Where (@?P tup) Return (@?f tup))))
                 _) _ ] =>
    let filter_dec := eval simpl in (@DecideableEnsembles.dec _ P _) in
        let idx_search_update_term := eval simpl in (ith3 indices idx) in
            let search_term_type' := eval simpl in (BagSearchTermType idx_search_update_term) in
                let search_term_matcher := eval simpl in (BagMatchSearchTerm idx_search_update_term) in
                    makeEvar search_term_type'
                             ltac: (fun search_term =>
                                      let eqv := fresh in
                                      assert (ExtensionalEq filter_dec (search_term_matcher search_term)) as eqv;
                                      [ find_search_term qs_schema idx filter_dec search_term
                                      |
                                      let H' := fresh in
                                      pose proof (@refine_BagFindBagCount
                                                    _
                                                   qs_schema indices
                                                   idx r_o r_n search_term P f H eqv) as H';
                                      fold_string_hyps_in H'; fold_heading_hyps_in H';
                                      rewrite H'; clear H' eqv
                                   ])
  | [ H : @DelegateToBag_AbsR ?qs_schema ?indices ?r_o ?r_n
      |- refine (Bind (Count For (UnConstrQuery_In _ ?idx (fun tup => Where (@?P tup) Return _)))
                 _) _ ] =>
    let filter_dec := eval simpl in (@DecideableEnsembles.dec _ P _) in
        let idx_search_update_term := eval simpl in (ith3 indices idx) in
            let search_term_type' := eval simpl in (BagSearchTermType idx_search_update_term) in
                let search_term_matcher := eval simpl in (BagMatchSearchTerm idx_search_update_term) in
                    makeEvar search_term_type'
                             ltac: (fun search_term =>
                                      let eqv := fresh in
                                      assert (ExtensionalEq filter_dec (search_term_matcher search_term)) as eqv;
                                      [ find_search_term qs_schema idx filter_dec search_term
                                      |
                                      let H' := fresh in
                                      pose proof (@refine_BagFindBagCount unit
                                                   qs_schema indices
                                                   idx r_o r_n search_term P (fun _ => tt) _ H eqv) as H';
                                      fold_string_hyps_in H'; fold_heading_hyps_in H';
                                      rewrite H'; clear H' eqv
                                      ])
  end.


Ltac implement_insert''' :=
  first [ implement_simple_For
            ltac:(find_simple_search_term
            ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
            ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
            ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm))
        | implement_Count
            ltac:(find_simple_search_term
            ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
            ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
            ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm))
        | implement_insert''].


Ltac  simplify_Query_Where ::=
    match goal with
    |- context [UnConstrQuery_In ?r_n ?Ridx (fun tup =>  Query_Where (@?P tup) _)] =>
    rewrite (fun ResultT =>
               @refine_UnConstrQuery_In_Query_Where_Cond _ r_n Ridx ResultT P);
      [ | intros;
          match goal with
            |- context [RDataTypeToRRecordType (SumType.inj_SumType ?y ?z ?x) <> ?q] =>
            case_eq (fin_eq_dec z q); simpl; intros ? ?; try discriminate;
            first [let H' := fresh in
                   assert (RDataTypeToRRecordType (SumType.inj_SumType y z x) <> q <-> True) as H' by
                         (rewrite RDataTypeToRRecordType_inj; intuition eauto);
                   set_evars; rewrite ?H', ?and_True_l, ?and_True_r, ?and_False_r, ?and_False_l
                  | let H' := fresh in
                    assert (RDataTypeToRRecordType (SumType.inj_SumType y z x) <> q <-> False) as H' by
                          (rewrite RDataTypeToRRecordType_inj; eauto; intuition eauto);
                    set_evars; rewrite ?H', ?and_True_l, ?and_True_r, ?and_False_r, ?and_False_l];
            finish honing
          | |- context [RDataTypeToRRecordType (SumType.inj_SumType ?y ?z ?x) = ?q] =>
            case_eq (fin_eq_dec z q); simpl; intros ? ?; try discriminate;
            first [let H' := fresh in
                   assert (RDataTypeToRRecordType (SumType.inj_SumType y z x) = q <-> True) as H' by
                         (rewrite RDataTypeToRRecordType_inj; intuition eauto);
                   set_evars; rewrite ?H', ?and_True_l, ?and_True_r, ?and_False_r, ?and_False_l
                  | let H' := fresh in
                    assert (RDataTypeToRRecordType (SumType.inj_SumType y z x) = q <-> False) as H' by
                          (rewrite RDataTypeToRRecordType_inj; eauto; intuition eauto);
                    set_evars; rewrite ?H', ?and_True_l, ?and_True_r, ?and_False_r, ?and_False_l
                  | rewrite RDataTypeToRRecordType_inj; eauto];
            finish honing
          | |- context [RDataTypeToRRecordType (SumType.inj_SumType ?y ?z ?x)] =>
            set_evars; rewrite !RDataTypeToRRecordType_inj; eauto; finish honing
          end]
    end.

    Ltac simplify_Query_Where' :=
      match goal with
      H : DelegateToBag_AbsR ?r_o ?r_n
      |- refine (Bind (For (UnConstrQuery_In ?r_o ?idx
                                             (fun tup => Where False (@?body tup)))) _)
                _ => rewrite (@refine_Query_In_Where_False _ _ _ r_o r_n idx body H)
      | H : DelegateToBag_AbsR ?r_o ?r_n
      |- refine (Bind (For (UnConstrQuery_In (qsSchema := ?qs_schema) ?r_o ?idx
                                             (fun tup => Where (?a = ?b /\ @?Q tup) (@?body tup)))) _)
                _ => rewrite (@refine_Query_In_Where_Const qs_schema _ _ _ _ r_o _ idx body Q a b H)
      | H : DelegateToBag_AbsR ?r_o ?r_n
        |- refine (Bind (For (UnConstrQuery_In (qsSchema := ?qs_schema) ?r_o ?idx
                                             (fun tup => Where (?a <> ?b /\ @?Q tup) (@?body tup)))) _)
                _ => rewrite (@refine_Query_In_Where_Const_neq qs_schema _ _ _ _ r_o _ idx body Q a b H)
      | H : DelegateToBag_AbsR ?r_o ?r_n
      |- refine (Bind (Count (For (UnConstrQuery_In ?r_o ?idx
                                             (fun tup => Where False (@?body tup))))) _)
                _ => rewrite (@refine_Count_Query_In_Where_False _ _ _ r_o r_n idx body H)
      | H : DelegateToBag_AbsR ?r_o ?r_n
      |- refine (Bind (Count (For (UnConstrQuery_In (qsSchema := ?qs_schema) ?r_o ?idx
                                             (fun tup => Where (?a = ?b /\ @?Q tup) (@?body tup))))) _)
                _ => rewrite (@refine_Count_Query_In_Where_Const qs_schema _ _ _ _ r_o _ idx body Q a b H)
      | H : DelegateToBag_AbsR ?r_o ?r_n
      |- refine (Bind (Count (For (UnConstrQuery_In (qsSchema := ?qs_schema) ?r_o ?idx
                                             (fun tup => Where (?a <> ?b /\ @?Q tup) (@?body tup))))) _)
                _ => rewrite (@refine_Count_Query_In_Where_Const_neq qs_schema _ _ _ _ r_o _ idx body Q a b H)
    end.

Theorem DnsManual :
  {DnsImpl : _ & refineADT DnsSpec DnsImpl}.
Proof.
  eexists; unfold DnsSpec.
  pose_string_hyps; pose_heading_hyps.
  drop_constraintsfrom_DNS.
  { (* Add Data. *)
    etransitivity.
    match goal with
      H : DropQSConstraints_AbsR ?r_o ?r_n
      |- refine (u <- QSInsert ?r_o ?Ridx ?tup;
                 @?k u) _ =>
      eapply (@QSInsertSpec_refine_subgoals_short_circuit _ _ r_o r_n Ridx tup); try exact H
    end; try set_refine_evar.
    - rewrite decides_True; finish honing.
    - simpl.
      rewrite refine_decides_forall_and;
        [
        | let a := fresh in
          intro a; split; [let H' := fresh in intros H'; pattern (indexedElement a); exact H' | intuition]
        | let a := fresh in
          intro a; split; [let H' := fresh in intros H'; pattern (indexedElement a); exact H' | intuition] ].
      rewrite refine_noDup_CNAME_check_dns by eauto.
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      match goal with
      |- refine (If_Then_Else ?c _ _) _ =>
      subst_refine_evar; eapply refine_if with (b := c);
        let H := fresh in
        intro H; set_refine_evar; try rewrite H; simpl
    end.
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      rewrite refine_no_usurp_authority_check by eauto.
      erewrite beq_RRecordType_trans by eauto.
      simpl.
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      rewrite refine_no_usurp_authority_check_dns by eauto.
      repeat doOne ltac:(drop_constraints)
                          drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    - simpl; set_evars; intros.
      rewrite refine_decides_forall_and;
        [
        | let a := fresh in
          intro a; split; [let H' := fresh in intros H'; pattern (indexedElement a); exact H' | intuition]
        | let a := fresh in
          intro a; split; [let H' := fresh in intros H'; pattern (indexedElement a); exact H' | intuition] ].
      setoid_rewrite refine_count_constraint_broken'.
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      rewrite refine_no_usurp_authority_check'_dns by eauto.
      repeat doOne ltac:(drop_constraints)
                          drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      repeat doOne ltac:(drop_constraints)
                          drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    - simpl; finish honing.
    - simpl; intros; finish honing.
    - intros. refine pick val _; eauto; simplify with monad laws.
      simpl; finish honing.
    - intros. refine pick val _; eauto; simplify with monad laws.
      simpl; finish honing.
    - simpl.
      repeat first [ progress simpl
                   | setoid_rewrite refine_bind_unit
                   | setoid_rewrite refine_bind_bind
                   | setoid_rewrite refine_If_Then_Else_Bind].
      finish honing.
  }
  { (* Process *)

    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    etransitivity.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    etransitivity.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (@MaxElementsUnConstrQuery_In DnsSchema Fin.F1 (fun r : resourceRecord => GetAttributeRaw r Fin.F1) (fst a1) r_n).
    rewrite refine_Process_Query.
    simplify with monad laws.
    setoid_rewrite refine_If_Opt_Then_Else_Bind.
    setoid_rewrite refineEquiv_bind_unit; simpl.
    finish honing.
    eassumption.
    finish honing.
    set_refine_evar; simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite refine_If_Opt_Then_Else_Bind.
    unfold H3. eapply refine_If_Opt_Then_Else'; intros; set_refine_evar.
    simplify with monad laws; simpl.
    rewrite refine_IfDec_true.
    simpl.
    rewrite (fun q => @refine_Singleton_Set'' r_o _ q _ _ _ H2 H4).

    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat econstructor.
    match type of H2 with
    | context[ UnConstrQuery_In (qsSchema := ?schem) ?r_n ?R _] =>
      pose proof (@For_UnConstrQuery_In_Where_Prop schem R r_n (fun r => RDataTypeToRRecordType r!sRDATA = CNAME /\ GetAttributeRaw r Fin.F1 = (fst a1)) _ _ H2);
        destruct a2; simpl in H4; try discriminate; injections;
          inversion H6; subst; intuition
    end.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    match goal with
      |- refine (If_Then_Else ?c _ _) _ =>
      subst_refine_evar; eapply refine_if with (b := c);
        let H := fresh in
        intro H; set_refine_evar; try rewrite H; simpl
    end.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite refine_If_Then_Else_false.
    rewrite refine_IfDec_true.
    rewrite (fun q => @refine_Singleton_Set' r_n q _ _ H4).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    apply (@For_UnConstrQuery_In_Where_Prop DnsSchema Fin.F1 r_n _ a3 _) in H4.
    rewrite Forall_forall in *.
    intros; eapply H4; eauto.
    rewrite <- negb_true_iff; eassumption.
    etransitivity; set_refine_evar.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    match goal with
      |- refine (If_Then_Else ?c _ _) _ =>
      subst_refine_evar; eapply refine_if with (b := c);
        let H := fresh in
        intro H; set_refine_evar; try rewrite H; simpl
    end.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite refine_IfDec_false.
    drop_constraints_drill.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    drop_constraints_drill.
    apply refine_foldComp; intros ? ?; set_refine_evar.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).

    destruct a4; simpl in *; try discriminate.
    intro.
    apply (@MaxElements_UnConstrQuery_In_Where_Prop DnsSchema Fin.F1 r_n) in H7.
    rewrite Forall_forall in *.
    eapply H7; simpl; intuition.
    apply DecideableEnsemble_And.
    simpl.
    setoid_rewrite refine_If_Else_Bind.

    rewrite refine_Process_Query_Imprecise_Match by eauto.

    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).

    (* 51s with apply decomposition lemmas.*)
    (* 73s with rewrite decomposition lemmas.*)
  }

  simpl.
  assert (forall (r : UnConstrQueryStructure
                        (DecomposeRawQueryStructureSchema DnsSchema Fin.F1
                                                          (Fin.FS (Fin.FS (Fin.FS Fin.F1))) ResourceRecordTypeTypes)), True).
  unfold DecomposeRawQueryStructureSchema, DecomposeSchema in *; simpl in *.
  pose_heading_hyps; auto.
  clear H.
  hone representation using (fun r_o (r_n : UnConstrQueryStructure qs_schema) =>
                               exists r_n',
                               @DecomposeRawQueryStructureSchema_AbsR
                                 _ DnsSchema Fin.F1 (Fin.FS (Fin.FS (Fin.FS (Fin.F1)))) _
                                 (SumType.SumType_index ResourceRecordTypeTypes)
                                 (SumType.SumType_proj ResourceRecordTypeTypes)
                                 (SumType.inj_SumType ResourceRecordTypeTypes)
                                 r_o (r_n', r_n)).
  { simplify with monad laws.
    refine pick val _.
    2: eexists _; apply (@DecomposeRawQueryStructureSchema_empty_AbsR _ DnsSchema).
    finish honing.
  }
  { destruct_ex; simplify with monad laws.
    simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (refine_UnConstrFreshIdx_DecomposeRawQueryStructureSchema_AbsR_Equiv H0).
    simpl; finish honing.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (refine_Iterate_Count_For_UnConstrQuery_In _ H0).
    unfold Iterate_Equiv_Count_For_UnConstrQuery_In_body; simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    setoid_rewrite Query_Where_And_Sym.
    setoid_rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simpl.
    Local Transparent UpdateUnConstrRelationInsertC.

    erewrite (DecomposeRawQueryStructureSchema_UpdateUnConstrRelationInsertC_eq _ _ H0);
      [ | eassumption | intros; set_refine_evar; refine pick val (snd r_n'); destruct r_n';
                        try eauto;
                        simplify with monad laws; simpl; try finish honing;
                        unfold H8; instantiate (1 := fun z => ret (snd z, true)); reflexivity].
    simpl.
    unfold UpdateUnConstrRelationInsertC at 1.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    setoid_rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    erewrite (DecomposeRawQueryStructureSchema_UpdateUnConstrRelationInsertC_eq _ _ H0);
      [ | eassumption | intros; set_refine_evar; refine pick val (snd r_n'); destruct r_n';
                        try eauto;
                        simplify with monad laws; simpl; try finish honing;
                        unfold H9; instantiate (1 := fun z => ret (snd z, true)); reflexivity].
    simpl.
    unfold UpdateUnConstrRelationInsertC at 1.
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (refine_Iterate_Count_For_UnConstrQuery_In _ H0).
    unfold Iterate_Equiv_Count_For_UnConstrQuery_In_body; simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simpl; simplify_Query_Where.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simpl; simplify_Query_Where.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simplify_Query_Where.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simplify_Query_Where.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    setoid_rewrite Query_Where_And_Sym.
    setoid_rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    erewrite (DecomposeRawQueryStructureSchema_UpdateUnConstrRelationInsertC_eq _ _ H0);
      [ | eassumption | intros; set_refine_evar; refine pick val (snd r_n'); destruct r_n';
                        try eauto;
                        simplify with monad laws; simpl; try finish honing;
                        unfold H8; instantiate (1 := fun z => ret (snd z, true)); reflexivity].
    simpl.
    simpl; unfold UpdateUnConstrRelationInsertC at 1.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    setoid_rewrite Query_Where_And_Sym.
    setoid_rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    erewrite (DecomposeRawQueryStructureSchema_UpdateUnConstrRelationInsertC_eq _ _ H0);
      [ | eassumption | intros; set_refine_evar; refine pick val (snd r_n'); destruct r_n';
                        try eauto;
                        simplify with monad laws; simpl; try finish honing;
                        unfold H9; instantiate (1 := fun z => ret (snd z, true)); reflexivity].
    simpl; unfold UpdateUnConstrRelationInsertC at 1.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    setoid_rewrite Query_Where_And_Sym.
    setoid_rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    erewrite (DecomposeRawQueryStructureSchema_UpdateUnConstrRelationInsertC_eq _ _ H0);
      [ | eassumption | intros; set_refine_evar; refine pick val (snd r_n'); destruct r_n';
                        try eauto;
                        simplify with monad laws; simpl; try finish honing;
                        unfold H4; instantiate (1 := fun z => ret (snd z, true)); reflexivity].
    simpl; unfold UpdateUnConstrRelationInsertC at 1.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    setoid_rewrite Query_Where_And_Sym.
    setoid_rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    erewrite (DecomposeRawQueryStructureSchema_UpdateUnConstrRelationInsertC_eq _ _ H0);
      [ | eassumption | intros; set_refine_evar; refine pick val (snd r_n'); destruct r_n';
                        try eauto;
                        simplify with monad laws; simpl; try finish honing;
                        unfold H5; instantiate (1 := fun z => ret (snd z, true)); reflexivity].
    simpl; unfold UpdateUnConstrRelationInsertC at 1.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto; finish honing.
  }
  { (* Process *)

    destruct_ex.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    rewrite (UnConstrQuery_In_Where_Map).
    rewrite refine_For_Map.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    drop_constraints_drill.
    simpl; finish honing.
    etransitivity.
    eapply refine_If_opt_hd_error_map; intros; try eauto.
    match goal with
      |- refine (If_Then_Else ?c _ _) _ =>
      subst_refine_evar; eapply refine_if with (b := c);
        let H := fresh in
        intro H; set_refine_evar; try rewrite H; simpl
    end.
    rewrite refine_decides_QType_match by eauto.
    simplify with monad laws.
    match goal with
      | |- context [GetAttributeRaw (Tuple_DecomposeRawQueryStructure_inj'
                                      (qs_schema := ?qs_schema)
                                      ?schemaIdx ?attrIdx ?a ?a_inj ?tag ?tup) ?attrIdx'] =>
          let eq := eval compute in (fin_eq_dec attrIdx attrIdx') in
              match eq with
              | left ?e =>
                let H := fresh in
                assert (GetAttributeRaw (Tuple_DecomposeRawQueryStructure_inj'
                                        (qs_schema := qs_schema)
                                        schemaIdx attrIdx a a_inj tag tup) attrIdx'
                        = a_inj tag (GetAttributeRaw tup  attrIdx')) as H by reflexivity;
                simpl in H; rewrite H; clear H
              |right ?e =>
               let H := fresh in
               assert (GetAttributeRaw (Tuple_DecomposeRawQueryStructure_inj'
                                       (qs_schema := qs_schema)
                                       schemaIdx attrIdx a a_inj tag tup) attrIdx'
                       = GetAttributeRaw tup attrIdx') as H by reflexivity;
               simpl in H; rewrite H; clear H
              end
    end.
    rewrite RDataTypeToRRecordType_inj.
    simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    refine pick val _; eauto.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    setoid_rewrite refine_If_Then_Bind.
    rewrite refine_Process_Query_Exact_Match by eassumption.
    match goal with
      |- refine (If_Then_Else ?c _ _) _ =>
      subst_refine_evar; eapply refine_if with (b := c);
        let H := fresh in
        intro H; set_refine_evar; try rewrite H; simpl
    end.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (refine_Iterate_For_UnConstrQuery_In _ H0).
    unfold Iterate_Equiv_For_UnConstrQuery_In_body; simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simpl; simplify_Query_Where.

    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simpl; simplify_Query_Where.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simplify_Query_Where.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    simplify_GetAttributeRaw_inj.
    simplify_Query_Where.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat subst_refine_evar; cbv beta; simpl; try finish honing.
    etransitivity.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    apply refine_MaxElements'.
    rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    rewrite (UnConstrQuery_In_Where_Map).
    rewrite refine_For_Bind.
    finish honing.
    finish honing.
    rewrite refine_MaxElements_map.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite refine_filter_Tuple_Decompose_inj'.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    apply refine_foldComp; intros ? ?; set_refine_evar.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (refine_Iterate_For_UnConstrQuery_In _ H0).
    unfold Iterate_Equiv_For_UnConstrQuery_In_body; simpl.
        doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite (refine_Iterate_For_UnConstrQuery_In _ H0).
    unfold Iterate_Equiv_For_UnConstrQuery_In_body; simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).

    repeat first
           [ simplify_GetAttributeRaw_inj
           | simplify_Query_Where ].
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat first
           [ simplify_GetAttributeRaw_inj
           | simplify_Query_Where ].
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat first
           [ simplify_GetAttributeRaw_inj
           | simplify_Query_Where ].
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat first
           [ simplify_GetAttributeRaw_inj
           | simplify_Query_Where ].
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    - rewrite (refine_Iterate_Count_For_UnConstrQuery_In _ H0).
      unfold Iterate_Equiv_Count_For_UnConstrQuery_In_body; simpl.
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                   drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      repeat first
             [ simplify_GetAttributeRaw_inj
             | simplify_Query_Where ].
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat first
           [ simplify_GetAttributeRaw_inj
           | simplify_Query_Where ].
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat first
           [ simplify_GetAttributeRaw_inj
           | simplify_Query_Where ].
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat first
           [ simplify_GetAttributeRaw_inj
           | simplify_Query_Where ].
    repeat doOne ltac:(drop_constraints)
                        drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    etransitivity.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    apply refine_MaxElements'.
    rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    rewrite (UnConstrQuery_In_Where_Map).
    rewrite refine_For_Bind.
    finish honing.
    finish honing.
    rewrite refine_MaxElements_map.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite refine_filter_Tuple_Decompose_inj'.
    simplify with monad laws.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    apply refine_foldComp; intros ? ?; set_refine_evar.
    rewrite (refine_Iterate_For_UnConstrQuery_In _ H0).
    unfold Iterate_Equiv_For_UnConstrQuery_In_body; simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    - simpl.
    etransitivity.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    apply refine_MaxElements'.
    rewrite (refine_QueryIn_Where _ _ H0).
    simplify_GetAttributeRaw_inj.
    rewrite (UnConstrQuery_In_Where_Map).
    rewrite refine_For_Bind.
    finish honing.
    finish honing.
    rewrite refine_MaxElements_map.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    rewrite refine_filter_Tuple_Decompose_inj'.
    simplify with monad laws.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    apply refine_foldComp; intros ? ?; set_refine_evar.
    rewrite (refine_Iterate_For_UnConstrQuery_In _ H0).
    unfold Iterate_Equiv_For_UnConstrQuery_In_body; simpl.
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    simplify_GetAttributeRaw_inj.
    repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
    - simpl.
    finish honing.

    - repeat doOne ltac:(drop_constraints)
                 drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      refine pick val _; eauto; finish honing.
    - repeat doOne ltac:(drop_constraints)
                          drop_constraints_drill ltac:(repeat subst_refine_evar; cbv beta; simpl; try finish honing).
      refine pick val _; eauto; finish honing.
  }
  simpl.
  pose {| prim_fst := [(EqualityIndex, @Fin.F1 3);
                       (FindStringPrefixIndex, @Fin.F1 3)];
          prim_snd := {|
          prim_fst := [(EqualityIndex, @Fin.F1 3);
                       (FindStringPrefixIndex, @Fin.F1 3)];
          prim_snd := {|
          prim_fst := [(EqualityIndex, @Fin.F1 3);
                       (FindStringPrefixIndex, @Fin.F1 3)];
          prim_snd := {|
          prim_fst := [(EqualityIndex, @Fin.F1 3);
                       (FindStringPrefixIndex, @Fin.F1 3)];
          prim_snd := () |} |} |} |}.

  Time let p' := eval unfold p in p in
           make_simple_indexes p'
                               ltac:(CombineCase6 BuildEarlyFindStringPrefixIndex ltac:(LastCombineCase6 BuildEarlyEqualityIndex))
                                      ltac:(CombineCase5 BuildLastStringFindPrefixIndex ltac:(LastCombineCase5 BuildLastEqualityIndex)).

  (* We should be doing automatic data structure selection here. *)
  { (* Constructor *)
      initializer.
  }

  {(* Add Data *)

    doOne implement_insert''
            ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
      set_evars) ltac:(finish honing).
    doOne implement_insert''
            ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
      set_evars) ltac:(finish honing).
    doOne implement_insert''
            ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
      set_evars) ltac:(finish honing).
    match goal with
      H : DelegateToBag_AbsR ?r_o ?r_n
      |- refine (l <- {idx | forall Ridx', UnConstrFreshIdx (GetUnConstrRelation ?r_o ?Ridx) idx }; _) _ =>
      let idx' := fresh in
      let idx_OK := fresh in
      destruct (@exists_UnConstrFreshIdx_Max _ _ _ _ H) as [idx idx_OK];
        refine pick val idx; [ | apply idx_OK]
    end.
    Local Opaque CallBagCount.
    repeat doOne ltac:(first [
                implement_Count
                  ltac:(find_simple_search_term
                          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
                                 ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
                                        ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm))
              | implement_insert''])
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    eauto.
    eauto.
    eauto.
    eauto.
    eauto.
    eauto.
  }
  { (* Process *)

    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    drop_constraints.
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    clear H1.
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).

   Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    idtac.
    rewrite refine_MaxPrefix.
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
   Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    apply refine_foldComp; intros ? ?; set_refine_evar.
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
   Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    subst_refine_evar; eapply refine_under_bind_both;
    try set_refine_evar; intros.
    repeat  doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    subst_refine_evar; eapply refine_under_bind_both;
    try set_refine_evar; intros.
    repeat  doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    subst_refine_evar; eapply refine_under_bind_both;
    try set_refine_evar; intros.
    repeat  doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    subst_refine_evar; eapply refine_under_bind_both;
    try set_refine_evar; intros.
    repeat  doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    subst_refine_evar; eapply refine_under_bind_both;
    try set_refine_evar; intros.
    repeat  doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    rewrite refine_unit_bind'.
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    subst_refine_evar; eapply refine_under_bind_both;
    try set_refine_evar; intros.
    repeat  doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    rewrite refine_unit_bind'.
    repeat doOne implement_insert'''
           ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    simplify_Query_Where'.
    subst_refine_evar; eapply refine_under_bind_both;
    try set_refine_evar; intros.
    repeat  doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    rewrite refine_unit_bind'.
    repeat doOne implement_insert'''
           ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    set_refine_evar.
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    rewrite refine_MaxPrefix.
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    apply refine_foldComp; intros ? ?; set_refine_evar.
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    rewrite refine_MaxPrefix.
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    Time doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    apply refine_foldComp; intros ? ?; set_refine_evar.
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
    repeat doOne implement_insert'''
          ltac:(master_implement_drill
          ltac:(CombineCase5 StringPrefixIndexUse EqIndexUse)
          ltac:(CombineCase10 createEarlyStringPrefixTerm createEarlyEqualityTerm)
          ltac:(CombineCase7 createLastStringPrefixTerm createLastEqualityTerm);
                set_evars) ltac:(finish honing).
  }

  simpl.

  (* Need to inline parsed fields.
     hone method "Process".
  { simpl in H2.
    rewrite H0.
    simplify with monad laws.
    rewrite refine_decode_packet.
    unfold ByteAligned_packetDecoderImpl'.
    simpl.
    simplify with monad laws.
    drop_constraints_drill.
    drop_constraints_drill.
   *)

  apply reflexivityT.
  Time Defined.

Time Definition DNSImpl := Eval simpl in (projT1 DnsManual).
Print DNSImpl.

End BinaryDns.