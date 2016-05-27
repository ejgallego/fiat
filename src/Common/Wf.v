(** * Miscellaneous Well-Foundedness Facts *)
Require Export Fiat.Common.Coq__8_4__8_5__Compat.
Require Import Coq.Setoids.Setoid Coq.Program.Program Coq.Program.Wf Coq.Arith.Wf_nat Coq.Classes.Morphisms Coq.Init.Wf.
Require Import Fiat.Common.Telescope.Core.
Require Import Fiat.Common.Telescope.Instances.
Require Import Fiat.Common.Telescope.Equality.
Require Import Fiat.Common.
Require Import Fiat.Common.Equality.

Set Implicit Arguments.

Scheme Induction for Acc Sort Prop.
Scheme Induction for Acc Sort Set.
Scheme Induction for Acc Sort Type.

Section wf.
  Global Instance well_founded_subrelation {A}
    : Proper (flip subrelation ==> impl) (@well_founded A).
  Proof.
    intros R R' HR Rwf a.
    induction (Rwf a) as [a Ra R'a].
    constructor; intros y Hy.
    apply R'a, HR, Hy.
  Defined.

  Inductive RT_closure {A} (R : relation A) : relation A :=
  | cinject {x y} : R x y -> RT_closure R x y
  | crefl {x} : RT_closure R x x
  | ctrans {x y z} : RT_closure R x y -> RT_closure R y z -> RT_closure R x z.

  Fixpoint Acc_subrelation {A} (R1 R2 : relation A) (v : A) (Hacc : Acc R1 v)
        (HR : forall x y, RT_closure R2 y v -> R2 x y -> R1 x y) {struct Hacc}
    : Acc R2 v.
  Proof.
    destruct Hacc as [Hacc].
    constructor.
    intros y Hy.
    specialize (fun pf => @Acc_subrelation A R1 R2 y (Hacc y pf)).
    specialize (@Acc_subrelation (HR _ _ (@crefl _ _ _) Hy)).
    apply Acc_subrelation; clear -HR Hy.
    intros x y' Hxy Hr2.
    apply HR; clear HR; [ | assumption ].
    clear -Hy Hxy.
    eapply ctrans; [ eassumption | eapply cinject; eassumption ].
  Defined.

  Section wf_acc_of.
    Context A (RA : relation A).

    Definition well_founded_acc_relation_of
              B (f : B -> A) (fA : forall b, Acc RA (f b))
      : relation B
      := fun b0 b1 => match fA b1 with
                      | Acc_intro fAb1 => exists pf,
                                          fAb1 (f b0) pf = fA b0
                      end.


    Lemma well_founded_well_founded_acc_relation_of B f fA
      : well_founded (@well_founded_acc_relation_of B f fA).
    Proof.
      intro b.
      constructor.
      unfold well_founded_acc_relation_of.
      generalize (fA b).
      generalize (f b).
      lazymatch goal with
      | [ |- forall a' wf', @?P a' wf' ]
        => apply (@Acc_ind_dep A RA P)
      end.
      intros a Ha IH y [pf Hy].
      constructor.
      intros z Hz.
      specialize (IH (f y) pf z).
      apply IH; clear IH.
      destruct Hy.
      apply Hz.
    Defined.

    Fixpoint Acc_RA_of B (f : B -> A) b (ac : Acc RA (f b))
      : Acc (fun x y => RA (f x) (f y)) b.
    Proof.
      refine match ac with
             | Acc_intro fg => Acc_intro _ (fun y Ry => @Acc_RA_of _ _ _ (fg _ _))
             end.
      assumption.
    Defined.

    Lemma well_founded_RA_of B (f : B -> A) (wf_A : well_founded RA)
      : well_founded (fun x y => RA (f x) (f y)).
    Proof.
      intro a.
      apply Acc_RA_of, wf_A.
    Defined.
  End wf_acc_of.

  Section wf_acc_of_option.
    Context A (RA : relation A).

    Definition well_founded_acc_relation_of_opt
              B (f : B -> option A) (fA : forall b, match f b with
                                                    | Some fb => Acc RA fb
                                                    | None => True
                                                    end)
      : relation B
      := fun b0 b1
         => match f b1 as fb1 return match fb1 with
                                     | Some fb => Acc RA fb
                                     | None => True
                                     end -> _
            with
            | Some fb1
              => fun fAb
                 => match fAb with
                    | Acc_intro fAb1
                      => match f b0 as fb0 return match fb0 with
                                                  | Some fb => Acc RA fb
                                                  | None => True
                                                  end -> _
                         with
                         | Some fb0
                           => fun fAb0 => exists pf,
                                  fAb1 fb0 pf = fAb0
                         | None => fun _ => False
                         end (fA b0)
                    end
            | None => fun _ => False
            end (fA b1).

    Lemma well_founded_well_founded_acc_relation_of_opt B f fA
      : well_founded (@well_founded_acc_relation_of_opt B f fA).
    Proof.
      intro b.
      constructor.
      unfold well_founded_acc_relation_of_opt.
      generalize (fA b).
      generalize (f b).
      intros [fb|].
      { revert fb.
        lazymatch goal with
        | [ |- forall a' wf', @?P a' wf' ]
          => apply (@Acc_ind_dep A RA P)
        end.
        intros a Ha IH y.
        constructor.
        generalize dependent (fA y).
        destruct (f y) as [fy|] eqn:Hfy.
        { intros y0 [pf Hy].
          intros z Hz.
          specialize (IH fy pf z).
          apply IH; clear IH.
          destruct Hy.
          apply Hz. }
        { intros ? []. } }
      { intros ?? []. }
    Defined.

    Fixpoint Acc_RA_of_opt B (f : B -> option A) b v (Heq : f b = Some v)
             (ac : Acc RA v) {struct ac}
      : Acc (fun x y => match f x, f y with
                        | Some fx, Some fy => RA fx fy
                        | _, _ => False
                        end) b.
    Proof.
      destruct ac as [fg].
      constructor.
      intros y Ry.
      specialize (fun v H Rv => Acc_RA_of_opt B f y v H (fg _ Rv)); clear fg.
      destruct (f y) as [fy|] eqn:Hfy.
      { specialize (Acc_RA_of_opt _ eq_refl).
        destruct (f b) as [fb|] eqn:Hfb.
        { inversion Heq; clear Heq; subst.
          specialize (Acc_RA_of_opt Ry).
          assumption. }
        { destruct Ry. } }
      { destruct Ry. }
    Defined.

    Lemma well_founded_RA_of_opt B (f : B -> option A) (wf_A : well_founded RA)
      : well_founded (fun x y => match f x, f y with
                                 | Some fx, Some fy => RA fx fy
                                 | _, _ => False
                                 end).
    Proof.
      intro a.
      destruct (f a) eqn:H.
      { eapply Acc_RA_of_opt, wf_A; eassumption. }
      { constructor.
        intro y.
        destruct (f y); [ rewrite H | ]; intros []. }
    Defined.
  End wf_acc_of_option.

  Section wf_prod.
    Context A B (RA : relation A) (RB : relation B).

    Definition prod_relation : relation (A * B)
      := fun ab a'b' =>
           RA (fst ab) (fst a'b') \/ (fst a'b' = fst ab /\ RB (snd ab) (snd a'b')).

    Fixpoint well_founded_prod_relation_helper
             a b
             (wf_A : Acc RA a) (wf_B : well_founded RB) {struct wf_A}
    : Acc prod_relation (a, b)
      := match wf_A with
           | Acc_intro fa => (fix wf_B_rec b' (wf_B' : Acc RB b') : Acc prod_relation (a, b')
                              := Acc_intro
                                   _
                                   (fun ab =>
                                      match ab as ab return prod_relation ab (a, b') -> Acc prod_relation ab with
                                        | (a'', b'') =>
                                          fun pf =>
                                            match pf with
                                              | or_introl pf'
                                                => @well_founded_prod_relation_helper
                                                     _ _
                                                     (fa _ pf')
                                                     wf_B
                                              | or_intror (conj pfa pfb)
                                                => match wf_B' with
                                                     | Acc_intro fb
                                                       => eq_rect
                                                            _
                                                            (fun a'' => Acc prod_relation (a'', b''))
                                                            (wf_B_rec _ (fb _ pfb))
                                                            _
                                                            pfa
                                                   end
                                            end
                                      end)
                             ) b (wf_B b)
         end.

    Definition well_founded_prod_relation : well_founded RA -> well_founded RB -> well_founded prod_relation.
    Proof.
      intros wf_A wf_B [a b]; hnf in *.
      apply well_founded_prod_relation_helper; auto.
    Defined.
  End wf_prod.

  Section wf_sig.
    Context A B (RA : relation A) (RB : forall a : A, relation (B a)).

    Definition sigT_relation : relation (sigT B)
      := fun ab a'b' =>
           RA (projT1 ab) (projT1 a'b') \/ (exists pf : projT1 a'b' = projT1 ab, RB (projT2 ab)
                                                                                    (eq_rect _ B (projT2 a'b') _ pf)).

    Fixpoint well_founded_sigT_relation_helper
             a b
             (wf_A : Acc RA a) (wf_B : forall a, well_founded (@RB a)) {struct wf_A}
    : Acc sigT_relation (existT _ a b).
    Proof.
      refine match wf_A with
               | Acc_intro fa => (fix wf_B_rec b' (wf_B' : Acc (@RB a) b') : Acc sigT_relation (existT _ a b')
                                  := Acc_intro
                                       _
                                       (fun ab =>
                                          match ab as ab return sigT_relation ab (existT _ a b') -> Acc sigT_relation ab with
                                            | existT a'' b'' =>
                                              fun pf =>
                                                match pf with
                                                  | or_introl pf'
                                                    => @well_founded_sigT_relation_helper
                                                         _ _
                                                         (fa _ pf')
                                                         wf_B
                                                  | or_intror (ex_intro pfa pfb)
                                                    => match wf_B' with
                                                         | Acc_intro fb
                                                           => _(*eq_rect
                                                            _
                                                            (fun a'' => Acc sigT_relation (existT B a'' _(*b''*)))
                                                            (wf_B_rec _ (fb _ _(*pfb*)))
                                                            _
                                                            pfa*)
                                                       end
                                                end
                                          end)
                                 ) b (wf_B a b)
             end;
      simpl in *.
      destruct pfa; simpl in *.
      exact (wf_B_rec _ (fb _ pfb)).
    Defined.

    Definition well_founded_sigT_relation : well_founded RA
                                            -> (forall a, well_founded (@RB a))
                                            -> well_founded sigT_relation.
    Proof.
      intros wf_A wf_B [a b]; hnf in *.
      apply well_founded_sigT_relation_helper; auto.
    Defined.
  End wf_sig.

  Section wf_projT1.
    Context A (B : A -> Type) (R : relation A).

    Definition projT1_relation : relation (sigT B)
      := fun ab a'b' =>
           R (projT1 ab) (projT1 a'b').

    Definition well_founded_projT1_relation : well_founded R -> well_founded projT1_relation.
    Proof.
      intros wf [a b]; hnf in *.
      induction (wf a) as [a H IH].
      constructor.
      intros y r.
      specialize (IH _ r (projT2 y)).
      destruct y.
      exact IH.
    Defined.
  End wf_projT1.

  Section wf_iterated_prod_of.
    Context A (R : relation A) (Rwf : well_founded R).

    Fixpoint iterated_prod (n : nat) : Type
      := match n with
         | 0 => unit
         | S n' => A * iterated_prod n'
         end%type.

    Fixpoint iterated_prod_relation {n} : relation (iterated_prod n)
      := match n return relation (iterated_prod n) with
         | 0 => fun _ _ => False
         | S n' => prod_relation R (@iterated_prod_relation n')
         end.

    Fixpoint nat_eq_transfer (P : nat -> Type) (n m : nat) : P n -> (P m) + (EqNat.beq_nat n m = false)
      := match n, m return P n -> (P m) + (EqNat.beq_nat n m = false) with
         | 0, 0 => fun x => inl x
         | S n', S m' => @nat_eq_transfer (fun v => P (S v)) n' m'
         | _, _ => fun _ => inr eq_refl
         end.

    Fixpoint nat_eq_transfer_refl (P : nat -> Type) (n : nat) : forall v : P n, nat_eq_transfer P n n v = inl v
      := match n return forall v : P n, nat_eq_transfer P n n v = inl v with
         | 0 => fun v => eq_refl
         | S n' => @nat_eq_transfer_refl (fun k => P (S k)) n'
         end.

    Fixpoint nat_eq_transfer_neq (P : nat -> Type) (n m : nat)
      : forall v : P n, (if EqNat.beq_nat n m as b return ((P m) + (b = false)) -> Prop
                         then fun _ => True
                         else fun v => v = inr eq_refl)
                          (nat_eq_transfer P n m v)
      := match n, m return forall v : P n, (if EqNat.beq_nat n m as b return ((P m) + (b = false)) -> Prop
                                            then fun _ => True
                                            else fun v => v = inr eq_refl)
                                             (nat_eq_transfer P n m v)
         with
         | 0, 0 => fun _ => I
         | S n', S m' => @nat_eq_transfer_neq (fun v => P (S v)) n' m'
         | _, _ => fun _ => eq_refl
         end.

    Definition iterated_prod_relation_of
               B (sz : B -> nat) (f : forall b, iterated_prod (sz b))
      : relation B
      := fun x y => match nat_eq_transfer _ (sz x) (sz y) (f x) with
                    | inl fx => iterated_prod_relation fx (f y)
                    | inr _ => False
                    end.

    Lemma well_founded_iterated_prod_relation {n} : well_founded (@iterated_prod_relation n).
    Proof.
      induction n as [|n IHn]; simpl.
      { constructor; intros ? []. }
      { apply well_founded_prod_relation; assumption. }
    Defined.

    Local Ltac handle_nat_eq_transfer
      := repeat lazymatch goal with
                | [ |- forall n0 n1, @?P n0 n1 ]
                  => let n0' := fresh "n" in
                     let n1' := fresh "n" in
                     let H := fresh in
                     let H' := fresh in
                     intros n0' n1';
                     destruct (@nat_eq_transfer (P n0') n0' n1') as [H|H];
                     [ clear n1'; revert n0'
                     | apply H
                     | lazymatch goal with
                       | [ |- appcontext[@nat_eq_transfer iterated_prod n1' n0'] ]
                         => pose proof (@nat_eq_transfer_neq iterated_prod n1' n0') as H';
                            cbv beta in *;
                            generalize dependent (nat_eq_transfer iterated_prod n1' n0');
                            let Heq := fresh in
                            destruct (EqNat.beq_nat n1' n0') eqn:Heq;
                            [ apply EqNat.beq_nat_true_iff in Heq; subst; rewrite <- EqNat.beq_nat_refl in H;
                              exfalso; clear -H; congruence
                            | ]
                       | [ |- appcontext[@nat_eq_transfer iterated_prod n0' n1'] ]
                         => pose proof (@nat_eq_transfer_neq iterated_prod n0' n1') as H';
                            cbv beta in *;
                            generalize dependent (nat_eq_transfer iterated_prod n0' n1');
                            rewrite H
                       end
                     ]
                end;
         repeat match goal with
                | _ => reflexivity
                | [ H : False |- _ ] => exfalso; exact H
                | [ H : forall v, _ = inr _ |- _ ] => rewrite H
                | _ => intro
                end.

    Lemma RT_closure_same_size B (sz : B -> nat) (f : forall b, iterated_prod (sz b))
          a b
          (H : RT_closure (iterated_prod_relation_of sz f) a b)
      : sz a = sz b.
    Proof.
      induction H as [x y H | | ].
      { unfold iterated_prod_relation_of in *.
        generalize dependent (f x).
        generalize dependent (f y).
        generalize dependent (sz x).
        generalize dependent (sz y).
        handle_nat_eq_transfer. }
      { reflexivity. }
      { etransitivity; eassumption. }
    Defined.

    Lemma well_founded_iterated_prod_relation_of
          B (sz : B -> nat) (f : forall b, iterated_prod (sz b))
      : well_founded (@iterated_prod_relation_of B sz f).
    Proof.
      intro b.
      pose proof (@well_founded_RA_of_opt (iterated_prod (sz b)) iterated_prod_relation B) as wf.
      specialize (wf (fun b' => match nat_eq_transfer _ (sz b') (sz b) (f b') with
                                | inl v => Some v
                                | inr _ => None
                                end)).
      specialize (wf well_founded_iterated_prod_relation).
      eapply Acc_subrelation; [ eapply wf | clear wf ].
      intros x y H.
      apply RT_closure_same_size in H.
      unfold iterated_prod_relation_of.
      generalize dependent (f b).
      generalize dependent (f x).
      generalize dependent (f y).
      generalize dependent (sz y).
      intros ??; subst.
      clear y.
      generalize dependent (sz b).
      generalize dependent (sz x).
      clear.
      handle_nat_eq_transfer.
      rewrite !nat_eq_transfer_refl in *.
      assumption.
    Defined.
  End wf_iterated_prod_of.
End wf.

Local Ltac Fix_eq_t F_ext Rwf :=
  intros;
  unfold Fix;
  rewrite <- Fix_F_eq;
  apply F_ext; intros;
  repeat match goal with
           | [ |- appcontext[Fix_F _ _ (?f ?x)] ] => generalize (f x)
         end;
  clear -F_ext Rwf;
  match goal with
    | [ |- forall x : Acc _ ?a, _ ] => induction (Rwf a)
  end;
  intros; rewrite <- !Fix_F_eq;
  apply F_ext; eauto.

Local Ltac Fix_Proper_t Fix_eq wf :=
  change (@flatten_forall_eq_relation) with (@flatten_forall_eq);
  change (@flatten_forall_eq_relation_with_assumption) with (@flatten_forall_eq_with_assumption);
  let H := fresh "H" in
  let a := fresh "a" in
  unfold forall_relation, pointwise_relation, respectful;
  intros ?? H a; repeat intro;
  induction (wf a);
  rewrite !Fix_eq; [ erewrite H; [ reflexivity | .. ] | .. ]; eauto; intros;
  [ etransitivity; [ symmetry; apply H; reflexivity | apply H; eassumption ]; reflexivity
  | etransitivity; [ apply H; eassumption | symmetry; apply H; reflexivity ]; reflexivity ].

Section FixV.
  Context A (B : A -> Telescope)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a, flattenT (B a) Type).

  Local Notation FixV := (@Fix A R Rwf (fun a : A => flatten_forall (P a))).

  Section F.
    Context (F : forall x : A, (forall y : A, R y x -> flatten_forall (P y)) -> flatten_forall (P x)).

    Definition FixV_eq
               (F_ext : forall x (f g : forall y, R y x -> flatten_forall (P y)),
                          (forall y (p : R y x), flatten_forall_eq (f y p) (g y p))
                          -> flatten_forall_eq (@F x f) (@F x g))
    : forall a, flatten_forall_eq (@FixV F a) (@F a (fun y (_ : R y a) => @FixV F y)).
    Proof. Fix_eq_t F_ext Rwf. Defined.

    Definition FixV_eq_with_assumption
               Q
               (F_ext : forall x (f g : forall y, R y x -> flatten_forall (P y)),
                          (forall y (p : R y x), flatten_forall_eq_with_assumption (Q y) (f y p) (g y p))
                          -> flatten_forall_eq_with_assumption (Q x) (@F x f) (@F x g))
    : forall a, flatten_forall_eq_with_assumption (Q a) (@FixV F a) (@F a (fun y (_ : R y a) => @FixV F y)).
    Proof. Fix_eq_t F_ext Rwf. Defined.

    Definition FixV_rect
               (Q : forall a, flattenT (Telescope_append (B a) (P a)) Type)
               (H0 : forall x, (forall y, R y x -> flatten_append_forall (@Q y) (@FixV F y))
                              -> flatten_append_forall (@Q x) (@F x (fun (y : A) (_ : R y x) => @FixV F y)))
               (F_ext : forall x (f g : forall y, R y x -> flatten_forall (@P y)),
                          (forall y (p : R y x), flatten_forall_eq (f y p) (g y p))
                          -> flatten_forall_eq (@F x f) (@F x g))
               a
    : flatten_append_forall (@Q a) (@FixV F a).
    Proof.
      induction (Rwf a).
      eapply flatten_append_forall_Proper; auto with nocore.
      symmetry; eapply FixV_eq; auto with nocore.
    Defined.
  End F.

  Global Instance FixV_Proper_eq
  : Proper
      ((forall_relation
          (fun a =>
             (forall_relation
                (fun a' =>
                   pointwise_relation
                     _
                     (flatten_forall_eq_relation)))
               ==> flatten_forall_eq_relation))
         ==> (forall_relation (fun a => flatten_forall_eq_relation)))
      FixV.
  Proof. Fix_Proper_t @FixV_eq Rwf. Qed.

  Global Instance FixV_Proper_eq_with_assumption
         Q
  : Proper
      ((forall_relation
          (fun a : A =>
             (forall_relation
                (fun a' : A =>
                   pointwise_relation
                     (R a' a)
                     (flatten_forall_eq_relation_with_assumption (Q a'))))
               ==> flatten_forall_eq_relation_with_assumption (Q a)))
         ==> (forall_relation (fun a => flatten_forall_eq_relation_with_assumption (Q a))))
      FixV.
  Proof. Fix_Proper_t @FixV_eq_with_assumption Rwf. Qed.
End FixV.

Arguments FixV_Proper_eq {A B R Rwf P} _ _ _ _.
Arguments FixV_Proper_eq_with_assumption {A B R Rwf P} _ _ _ _ _.

Local Arguments flatten_forall / .
Local Arguments flattenT / .
Local Arguments flatten_forall_eq / .
Local Arguments flatten_forall_eq_relation / .
Local Arguments flatten_forall_eq_with_assumption / .
Local Arguments flatten_forall_eq_relation_with_assumption / .
Local Arguments flatten_append_forall / .

Local Notation type_of x := ((fun T (y : T) => T) _ x).

Section FixVTransfer.
  Context A (B B' : A -> Telescope)
          (f0 : forall a, flattenT_sig (B a) -> flattenT_sig (B' a))
          (g0 : forall a, flattenT_sig (B' a) -> flattenT_sig (B a))
          (sect : forall a x, g0 a (f0 a x) = x)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a, flattenT (B a) Type).

  Let P' : forall a, flattenT (B' a) Type
    := fun a => flattenT_unapply (fun x => flattenT_apply (P a) (g0 _ x)).

  Local Notation FixV := (@Fix A R Rwf (fun a : A => flatten_forall (P a))).
  Local Notation FixV' := (@Fix A R Rwf (fun a : A => flatten_forall (P' a))).

  Section F.
    Context (F : forall x : A, (forall y : A, R y x -> flatten_forall (P y)) -> flatten_forall (P x)).

    Let transfer
    : forall y,
        flatten_forall
          (flattenT_unapply
             (fun x : flattenT_sig (B y) => flattenT_apply (P' y) (f0 y x)))
        -> flatten_forall (P y).
    Proof.
      intro y.
      refine (flatten_forall_eq_rect
                (transitivity
                   ((_ : Proper (pointwise_relation _ _ ==> _) flattenT_unapply)
                      _ _
                      (fun x' => transitivity
                                   (symmetry (flattenT_apply_unapply _ _))
                                   (f_equal (flattenT_apply _) (sect _ _))))
                   (symmetry (flattenT_unapply_apply _)))).
    Defined.

    Let transfer'
    : forall a,
        flatten_forall (P a)
        -> flatten_forall (P' a).
    Proof.
      intro a.
      refine (fun f' => flatten_forall_unapply (fun x' => flatten_forall_apply f' (g0 _ x'))).
    Defined.

    Let untransfer'
    : forall a,
        flatten_forall (P' a)
        -> flatten_forall (P a).
    Proof.
      intro a.
      refine (fun f' => _).
      refine (transfer
                _
                (flatten_forall_unapply (fun x => flatten_forall_apply f' (f0 _ x)))).
    Defined.

    Let F' : forall x : A, (forall y : A, R y x -> flatten_forall (P' y)) -> flatten_forall (P' x)
      := fun a F' => transfer' _ (@F a (fun y pf => transfer _ (flatten_forall_unapply (fun x => flatten_forall_apply (F' y pf) (f0 _ x))))).


    Context (F_ext : forall x (f g : forall y, R y x -> flatten_forall (P y)),
                       (forall y (p : R y x), flatten_forall_eq (f y p) (g y p))
                       -> flatten_forall_eq (@F x f) (@F x g)).

    Lemma F'_ext
    : forall x (f g : forall y, R y x -> flatten_forall (P' y)),
        (forall y (p : R y x), flatten_forall_eq (f y p) (g y p))
        -> flatten_forall_eq (@F' x f) (@F' x g).
    Proof.
      intros x f' g' IH.
      subst F' transfer transfer'; cbv beta.
      apply (_ : Proper (forall_relation _ ==> _) flatten_forall_unapply); intro.
      apply flatten_forall_apply_Proper.
      apply F_ext; intros.
      refine ((_ : Proper (flatten_forall_eq ==> _) (@flatten_forall_eq_rect _ _ _ _)) _ _ _).
      apply (_ : Proper (forall_relation _ ==> _) flatten_forall_unapply); intro.
      apply flatten_forall_apply_Proper.
      apply IH.
    Qed.

    Definition FixV_transfer_eq
               a
    : flatten_forall_eq (@FixV F a) (untransfer' _ (@FixV' F' a)).
    Proof.
      induction (Rwf a).
      rewrite FixV_eq by eauto with nocore.
      etransitivity_rev _.
      { unfold transfer, untransfer'; cbv beta.
        apply flatten_forall_eq_rect_Proper, flatten_forall_unapply_Proper; intro.
        apply flatten_forall_apply_Proper.
        rewrite FixV_eq by auto using F'_ext with nocore.
        reflexivity. }
      etransitivity.
      { apply F_ext; intros.
        set_evars.
        match goal with
          | [ H : forall y r, flatten_forall_eq _ _ |- _ ] => rewrite H by assumption
        end.
        match goal with
          | [ |- ?R ?a (?e ?x ?y) ]
            => revert x y
        end.
        match goal with
          | [ H := ?e |- _ ] => is_evar e; subst H
        end.
        match goal with
          | [ |- forall x y, ?R (@?LHS x y) (?RHS x y) ]
            => unify LHS RHS; cbv beta
        end.
        reflexivity. }
      lazymatch goal with
        | [ |- appcontext[FixV' ?F] ]
          => generalize (FixV' F)
      end.
      subst F'; cbv beta.
      subst untransfer' transfer transfer'; cbv beta.
      intro.
      rewrite flatten_forall_eq_rect_trans.
      match goal with
        | [ |- appcontext[flatten_forall_eq_rect
                            (flattenT_unapply_Proper ?P ?Q ?H)
                            (flatten_forall_unapply ?f)] ]
          => rewrite (@flatten_forall_eq_rect_flattenT_unapply_Proper _ P Q H f)
      end.
      etransitivity_rev _.
      { apply flatten_forall_eq_rect_Proper.
        apply flatten_forall_unapply_Proper; intro.
        match goal with
          | [ |- appcontext[@transitivity _ (@eq ?A) ?P] ]
            => change (@transitivity _ (@eq ?A) P) with (@eq_trans A)
        end.
        match goal with
          | [ |- appcontext[@symmetry _ (@eq ?A) ?P] ]
            => change (@symmetry _ (@eq ?A) P) with (@eq_sym A)
        end.
        set_evars.
        rewrite @transport_pp.
        match goal with
          | [ |- appcontext G[eq_rect _ (fun T => T) (flatten_forall_apply (flatten_forall_unapply ?k) ?x0) _ (eq_sym (flattenT_apply_unapply ?f1 ?x0))] ]
            => let H := fresh in
               pose proof (@eq_rect_symmetry_flattenT_apply_unapply _ f1 x0 k) as H;
                 cbv beta in H |- *;
                 let RHS := match type of H with _ = ?RHS => constr:(RHS) end in
                 let LHS := match type of H with ?LHS = _ => constr:(LHS) end in
                 let G' := context G[LHS] in
                 change G';
                   rewrite H;
                   clear H
        end.
        match goal with
          | [ |- context[f_equal _ ?p] ]
            => destruct p; unfold f_equal; simpl @eq_rect
        end.
        subst_body.
        reflexivity. }
      rewrite flatten_forall_eq_rect_symmetry_flattenT_unapply_apply.
      apply F_ext; intros.
      reflexivity.
    Qed.
  End F.
End FixVTransfer.

Section Fix_rect.
  Context (A : Type).
  Local Notation T := (fun _ : A => bottom).

  Let Fix_rect' := @FixV_rect A T.
  Let Fix_rect'T := Eval simpl in type_of Fix_rect'.

  Let Fix_Proper_eq' := @FixV_Proper_eq A T.
  Let Fix_Proper_eq'T := Eval simpl in type_of Fix_Proper_eq'.

  Let Fix_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T.
  Let Fix_Proper_eq_with_assumption'T := Eval simpl in type_of Fix_Proper_eq_with_assumption'.

  Definition Fix_rect : Fix_rect'T := Fix_rect'.
  Definition Fix_Proper_eq : Fix_Proper_eq'T := Fix_Proper_eq'.
  Definition Fix_Proper_eq_with_assumption : Fix_Proper_eq_with_assumption'T := Fix_Proper_eq_with_assumption'.
End Fix_rect.

Arguments Fix_Proper_eq {A R Rwf P} _ _ _ _.
Arguments Fix_Proper_eq_with_assumption {A R Rwf P} _ _ _ _ _ _.
Global Existing Instance Fix_Proper_eq.
Global Existing Instance Fix_Proper_eq_with_assumption.

(** A variant of [Fix] that has a nice [Fix_eq] for functions which
    doesn't require [functional_extensionality]. *)
(* Following code generated by the following Python script:
<<
ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
alpha = ALPHA.lower()
for fixn in range(1, 11):
    print(r"""Section Fix%(fixn)d.""" % locals())
    def make_forall(n, pat, skip_forall=0):
        mycur = ''
        if n > skip_forall + 1:
            mycur += 'forall ' + ' '.join(alpha[skip_forall:n-1]) + ', '
        mycur2 = ''
        if n > 1:
            mycur2 += ' ' + ' '.join(alpha[:n-1])
        return mycur + (pat % mycur2)

    cur = '  Context A'
    for j in range(1, fixn + 1):
        cur += ' (%s : ' % ALPHA[j]
        cur += make_forall(j, '%s%%s -> Type)' % ALPHA[j-1])
    print(cur)
    print(r"""          (R : A -> A -> Prop) (Rwf : well_founded R)""")
    cur = "          (P : "
    cur += make_forall(j+1, '%s%%s -> Type).' % ALPHA[j])
    print(cur)
    print("")
    cur = "  Local Notation Fix%d := (@Fix A R Rwf (fun a : A => %s))."
    cur = cur % (j, make_forall(j+2, '@P%s', skip_forall=1))
    print(cur)
    def make_tele(chars, final, append=''):
        if chars:
            return '(fun %s => tele _ %s)' % (chars[0], make_tele(chars[1:], final, append + ' ' + chars[0]))
        else:
            return '(fun _ : %s%s => bottom)' % (final, append)
    print('  Local Notation T := %s.' % make_tele(alpha[:fixn], '@' + ALPHA[fixn]))
    fix_underscores = ' '.join('_' for i in range(fixn + 4))
    letters = ' '.join(ALPHA[:fixn+1])
    preletters = ' '.join(ALPHA[:fixn])
    print(r"""
  Let Fix%(fixn)d_eq' := @FixV_eq A T R Rwf P.
  Let Fix%(fixn)d_eq'T := Eval simpl in type_of Fix%(fixn)d_eq'.

  Let Fix%(fixn)d_rect' := @FixV_rect A T R Rwf P.
  Let Fix%(fixn)d_rect'T := Eval simpl in type_of Fix%(fixn)d_rect'.

  Let Fix%(fixn)d_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix%(fixn)d_Proper_eq'T := Eval simpl in type_of Fix%(fixn)d_Proper_eq'.

  Let Fix%(fixn)d_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix%(fixn)d_Proper_eq_with_assumption'T := Eval simpl in type_of Fix%(fixn)d_Proper_eq_with_assumption'.

  Definition Fix%(fixn)d_eq : Fix%(fixn)d_eq'T := Fix%(fixn)d_eq'.
  Definition Fix%(fixn)d_rect : Fix%(fixn)d_rect'T := Fix%(fixn)d_rect'.
  Definition Fix%(fixn)d_Proper_eq : Fix%(fixn)d_Proper_eq'T := Fix%(fixn)d_Proper_eq'.
  Definition Fix%(fixn)d_Proper_eq_with_assumption : Fix%(fixn)d_Proper_eq_with_assumption'T := Fix%(fixn)d_Proper_eq_with_assumption'.
End Fix%(fixn)d.

Arguments Fix%(fixn)d_Proper_eq {%(letters)s R Rwf P} %(fix_underscores)s.
Arguments Fix%(fixn)d_Proper_eq_with_assumption {%(letters)s R Rwf P} _ _ %(fix_underscores)s.
Global Existing Instance Fix%(fixn)d_Proper_eq.
Global Existing Instance Fix%(fixn)d_Proper_eq_with_assumption.
""" % locals())
>> *)
Section Fix1.
  Context A (B : A -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a, B a -> Type).

  Local Notation Fix1 := (@Fix A R Rwf (fun a : A => forall b, @P a b)).
  Local Notation T := (fun a => tele _ (fun _ : @B a => bottom)).

  Let Fix1_eq' := @FixV_eq A T R Rwf P.
  Let Fix1_eq'T := Eval simpl in type_of Fix1_eq'.

  Let Fix1_rect' := @FixV_rect A T R Rwf P.
  Let Fix1_rect'T := Eval simpl in type_of Fix1_rect'.

  Let Fix1_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix1_Proper_eq'T := Eval simpl in type_of Fix1_Proper_eq'.

  Let Fix1_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix1_Proper_eq_with_assumption'T := Eval simpl in type_of Fix1_Proper_eq_with_assumption'.

  Definition Fix1_eq : Fix1_eq'T := Fix1_eq'.
  Definition Fix1_rect : Fix1_rect'T := Fix1_rect'.
  Definition Fix1_Proper_eq : Fix1_Proper_eq'T := Fix1_Proper_eq'.
  Definition Fix1_Proper_eq_with_assumption : Fix1_Proper_eq_with_assumption'T := Fix1_Proper_eq_with_assumption'.
End Fix1.

Arguments Fix1_Proper_eq {A B R Rwf P} _ _ _ _ _.
Arguments Fix1_Proper_eq_with_assumption {A B R Rwf P} _ _ _ _ _ _ _.
Global Existing Instance Fix1_Proper_eq.
Global Existing Instance Fix1_Proper_eq_with_assumption.

Section Fix2.
  Context A (B : A -> Type) (C : forall a, B a -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b, C a b -> Type).

  Local Notation Fix2 := (@Fix A R Rwf (fun a : A => forall b c, @P a b c)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun _ : @C a b => bottom))).

  Let Fix2_eq' := @FixV_eq A T R Rwf P.
  Let Fix2_eq'T := Eval simpl in type_of Fix2_eq'.

  Let Fix2_rect' := @FixV_rect A T R Rwf P.
  Let Fix2_rect'T := Eval simpl in type_of Fix2_rect'.

  Let Fix2_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix2_Proper_eq'T := Eval simpl in type_of Fix2_Proper_eq'.

  Let Fix2_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix2_Proper_eq_with_assumption'T := Eval simpl in type_of Fix2_Proper_eq_with_assumption'.

  Definition Fix2_eq : Fix2_eq'T := Fix2_eq'.
  Definition Fix2_rect : Fix2_rect'T := Fix2_rect'.
  Definition Fix2_Proper_eq : Fix2_Proper_eq'T := Fix2_Proper_eq'.
  Definition Fix2_Proper_eq_with_assumption : Fix2_Proper_eq_with_assumption'T := Fix2_Proper_eq_with_assumption'.
End Fix2.

Arguments Fix2_Proper_eq {A B C R Rwf P} _ _ _ _ _ _.
Arguments Fix2_Proper_eq_with_assumption {A B C R Rwf P} _ _ _ _ _ _ _ _.
Global Existing Instance Fix2_Proper_eq.
Global Existing Instance Fix2_Proper_eq_with_assumption.

Section Fix3.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c, D a b c -> Type).

  Local Notation Fix3 := (@Fix A R Rwf (fun a : A => forall b c d, @P a b c d)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun _ : @D a b c => bottom)))).

  Let Fix3_eq' := @FixV_eq A T R Rwf P.
  Let Fix3_eq'T := Eval simpl in type_of Fix3_eq'.

  Let Fix3_rect' := @FixV_rect A T R Rwf P.
  Let Fix3_rect'T := Eval simpl in type_of Fix3_rect'.

  Let Fix3_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix3_Proper_eq'T := Eval simpl in type_of Fix3_Proper_eq'.

  Let Fix3_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix3_Proper_eq_with_assumption'T := Eval simpl in type_of Fix3_Proper_eq_with_assumption'.

  Definition Fix3_eq : Fix3_eq'T := Fix3_eq'.
  Definition Fix3_rect : Fix3_rect'T := Fix3_rect'.
  Definition Fix3_Proper_eq : Fix3_Proper_eq'T := Fix3_Proper_eq'.
  Definition Fix3_Proper_eq_with_assumption : Fix3_Proper_eq_with_assumption'T := Fix3_Proper_eq_with_assumption'.
End Fix3.

Arguments Fix3_Proper_eq {A B C D R Rwf P} _ _ _ _ _ _ _.
Arguments Fix3_Proper_eq_with_assumption {A B C D R Rwf P} _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix3_Proper_eq.
Global Existing Instance Fix3_Proper_eq_with_assumption.

Section Fix4.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type) (E : forall a b c, D a b c -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c d, E a b c d -> Type).

  Local Notation Fix4 := (@Fix A R Rwf (fun a : A => forall b c d e, @P a b c d e)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun d => tele _ (fun _ : @E a b c d => bottom))))).

  Let Fix4_eq' := @FixV_eq A T R Rwf P.
  Let Fix4_eq'T := Eval simpl in type_of Fix4_eq'.

  Let Fix4_rect' := @FixV_rect A T R Rwf P.
  Let Fix4_rect'T := Eval simpl in type_of Fix4_rect'.

  Let Fix4_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix4_Proper_eq'T := Eval simpl in type_of Fix4_Proper_eq'.

  Let Fix4_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix4_Proper_eq_with_assumption'T := Eval simpl in type_of Fix4_Proper_eq_with_assumption'.

  Definition Fix4_eq : Fix4_eq'T := Fix4_eq'.
  Definition Fix4_rect : Fix4_rect'T := Fix4_rect'.
  Definition Fix4_Proper_eq : Fix4_Proper_eq'T := Fix4_Proper_eq'.
  Definition Fix4_Proper_eq_with_assumption : Fix4_Proper_eq_with_assumption'T := Fix4_Proper_eq_with_assumption'.
End Fix4.

Arguments Fix4_Proper_eq {A B C D E R Rwf P} _ _ _ _ _ _ _ _.
Arguments Fix4_Proper_eq_with_assumption {A B C D E R Rwf P} _ _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix4_Proper_eq.
Global Existing Instance Fix4_Proper_eq_with_assumption.

Section Fix5.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type) (E : forall a b c, D a b c -> Type) (F : forall a b c d, E a b c d -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c d e, F a b c d e -> Type).

  Local Notation Fix5 := (@Fix A R Rwf (fun a : A => forall b c d e f, @P a b c d e f)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun d => tele _ (fun e => tele _ (fun _ : @F a b c d e => bottom)))))).

  Let Fix5_eq' := @FixV_eq A T R Rwf P.
  Let Fix5_eq'T := Eval simpl in type_of Fix5_eq'.

  Let Fix5_rect' := @FixV_rect A T R Rwf P.
  Let Fix5_rect'T := Eval simpl in type_of Fix5_rect'.

  Let Fix5_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix5_Proper_eq'T := Eval simpl in type_of Fix5_Proper_eq'.

  Let Fix5_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix5_Proper_eq_with_assumption'T := Eval simpl in type_of Fix5_Proper_eq_with_assumption'.

  Definition Fix5_eq : Fix5_eq'T := Fix5_eq'.
  Definition Fix5_rect : Fix5_rect'T := Fix5_rect'.
  Definition Fix5_Proper_eq : Fix5_Proper_eq'T := Fix5_Proper_eq'.
  Definition Fix5_Proper_eq_with_assumption : Fix5_Proper_eq_with_assumption'T := Fix5_Proper_eq_with_assumption'.
End Fix5.

Arguments Fix5_Proper_eq {A B C D E F R Rwf P} _ _ _ _ _ _ _ _ _.
Arguments Fix5_Proper_eq_with_assumption {A B C D E F R Rwf P} _ _ _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix5_Proper_eq.
Global Existing Instance Fix5_Proper_eq_with_assumption.

Section Fix6.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type) (E : forall a b c, D a b c -> Type) (F : forall a b c d, E a b c d -> Type) (G : forall a b c d e, F a b c d e -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c d e f, G a b c d e f -> Type).

  Local Notation Fix6 := (@Fix A R Rwf (fun a : A => forall b c d e f g, @P a b c d e f g)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun d => tele _ (fun e => tele _ (fun f => tele _ (fun _ : @G a b c d e f => bottom))))))).

  Let Fix6_eq' := @FixV_eq A T R Rwf P.
  Let Fix6_eq'T := Eval simpl in type_of Fix6_eq'.

  Let Fix6_rect' := @FixV_rect A T R Rwf P.
  Let Fix6_rect'T := Eval simpl in type_of Fix6_rect'.

  Let Fix6_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix6_Proper_eq'T := Eval simpl in type_of Fix6_Proper_eq'.

  Let Fix6_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix6_Proper_eq_with_assumption'T := Eval simpl in type_of Fix6_Proper_eq_with_assumption'.

  Definition Fix6_eq : Fix6_eq'T := Fix6_eq'.
  Definition Fix6_rect : Fix6_rect'T := Fix6_rect'.
  Definition Fix6_Proper_eq : Fix6_Proper_eq'T := Fix6_Proper_eq'.
  Definition Fix6_Proper_eq_with_assumption : Fix6_Proper_eq_with_assumption'T := Fix6_Proper_eq_with_assumption'.
End Fix6.

Arguments Fix6_Proper_eq {A B C D E F G R Rwf P} _ _ _ _ _ _ _ _ _ _.
Arguments Fix6_Proper_eq_with_assumption {A B C D E F G R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix6_Proper_eq.
Global Existing Instance Fix6_Proper_eq_with_assumption.

Section Fix7.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type) (E : forall a b c, D a b c -> Type) (F : forall a b c d, E a b c d -> Type) (G : forall a b c d e, F a b c d e -> Type) (H : forall a b c d e f, G a b c d e f -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c d e f g, H a b c d e f g -> Type).

  Local Notation Fix7 := (@Fix A R Rwf (fun a : A => forall b c d e f g h, @P a b c d e f g h)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun d => tele _ (fun e => tele _ (fun f => tele _ (fun g => tele _ (fun _ : @H a b c d e f g => bottom)))))))).

  Let Fix7_eq' := @FixV_eq A T R Rwf P.
  Let Fix7_eq'T := Eval simpl in type_of Fix7_eq'.

  Let Fix7_rect' := @FixV_rect A T R Rwf P.
  Let Fix7_rect'T := Eval simpl in type_of Fix7_rect'.

  Let Fix7_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix7_Proper_eq'T := Eval simpl in type_of Fix7_Proper_eq'.

  Let Fix7_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix7_Proper_eq_with_assumption'T := Eval simpl in type_of Fix7_Proper_eq_with_assumption'.

  Definition Fix7_eq : Fix7_eq'T := Fix7_eq'.
  Definition Fix7_rect : Fix7_rect'T := Fix7_rect'.
  Definition Fix7_Proper_eq : Fix7_Proper_eq'T := Fix7_Proper_eq'.
  Definition Fix7_Proper_eq_with_assumption : Fix7_Proper_eq_with_assumption'T := Fix7_Proper_eq_with_assumption'.
End Fix7.

Arguments Fix7_Proper_eq {A B C D E F G H R Rwf P} _ _ _ _ _ _ _ _ _ _ _.
Arguments Fix7_Proper_eq_with_assumption {A B C D E F G H R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix7_Proper_eq.
Global Existing Instance Fix7_Proper_eq_with_assumption.

Section Fix8.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type) (E : forall a b c, D a b c -> Type) (F : forall a b c d, E a b c d -> Type) (G : forall a b c d e, F a b c d e -> Type) (H : forall a b c d e f, G a b c d e f -> Type) (I : forall a b c d e f g, H a b c d e f g -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c d e f g h, I a b c d e f g h -> Type).

  Local Notation Fix8 := (@Fix A R Rwf (fun a : A => forall b c d e f g h i, @P a b c d e f g h i)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun d => tele _ (fun e => tele _ (fun f => tele _ (fun g => tele _ (fun h => tele _ (fun _ : @I a b c d e f g h => bottom))))))))).

  Let Fix8_eq' := @FixV_eq A T R Rwf P.
  Let Fix8_eq'T := Eval simpl in type_of Fix8_eq'.

  Let Fix8_rect' := @FixV_rect A T R Rwf P.
  Let Fix8_rect'T := Eval simpl in type_of Fix8_rect'.

  Let Fix8_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix8_Proper_eq'T := Eval simpl in type_of Fix8_Proper_eq'.

  Let Fix8_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix8_Proper_eq_with_assumption'T := Eval simpl in type_of Fix8_Proper_eq_with_assumption'.

  Definition Fix8_eq : Fix8_eq'T := Fix8_eq'.
  Definition Fix8_rect : Fix8_rect'T := Fix8_rect'.
  Definition Fix8_Proper_eq : Fix8_Proper_eq'T := Fix8_Proper_eq'.
  Definition Fix8_Proper_eq_with_assumption : Fix8_Proper_eq_with_assumption'T := Fix8_Proper_eq_with_assumption'.
End Fix8.

Arguments Fix8_Proper_eq {A B C D E F G H I R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _.
Arguments Fix8_Proper_eq_with_assumption {A B C D E F G H I R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix8_Proper_eq.
Global Existing Instance Fix8_Proper_eq_with_assumption.

Section Fix9.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type) (E : forall a b c, D a b c -> Type) (F : forall a b c d, E a b c d -> Type) (G : forall a b c d e, F a b c d e -> Type) (H : forall a b c d e f, G a b c d e f -> Type) (I : forall a b c d e f g, H a b c d e f g -> Type) (J : forall a b c d e f g h, I a b c d e f g h -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c d e f g h i, J a b c d e f g h i -> Type).

  Local Notation Fix9 := (@Fix A R Rwf (fun a : A => forall b c d e f g h i j, @P a b c d e f g h i j)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun d => tele _ (fun e => tele _ (fun f => tele _ (fun g => tele _ (fun h => tele _ (fun i => tele _ (fun _ : @J a b c d e f g h i => bottom)))))))))).

  Let Fix9_eq' := @FixV_eq A T R Rwf P.
  Let Fix9_eq'T := Eval simpl in type_of Fix9_eq'.

  Let Fix9_rect' := @FixV_rect A T R Rwf P.
  Let Fix9_rect'T := Eval simpl in type_of Fix9_rect'.

  Let Fix9_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix9_Proper_eq'T := Eval simpl in type_of Fix9_Proper_eq'.

  Let Fix9_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix9_Proper_eq_with_assumption'T := Eval simpl in type_of Fix9_Proper_eq_with_assumption'.

  Definition Fix9_eq : Fix9_eq'T := Fix9_eq'.
  Definition Fix9_rect : Fix9_rect'T := Fix9_rect'.
  Definition Fix9_Proper_eq : Fix9_Proper_eq'T := Fix9_Proper_eq'.
  Definition Fix9_Proper_eq_with_assumption : Fix9_Proper_eq_with_assumption'T := Fix9_Proper_eq_with_assumption'.
End Fix9.

Arguments Fix9_Proper_eq {A B C D E F G H I J R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _ _.
Arguments Fix9_Proper_eq_with_assumption {A B C D E F G H I J R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix9_Proper_eq.
Global Existing Instance Fix9_Proper_eq_with_assumption.

Section Fix10.
  Context A (B : A -> Type) (C : forall a, B a -> Type) (D : forall a b, C a b -> Type) (E : forall a b c, D a b c -> Type) (F : forall a b c d, E a b c d -> Type) (G : forall a b c d e, F a b c d e -> Type) (H : forall a b c d e f, G a b c d e f -> Type) (I : forall a b c d e f g, H a b c d e f g -> Type) (J : forall a b c d e f g h, I a b c d e f g h -> Type) (K : forall a b c d e f g h i, J a b c d e f g h i -> Type)
          (R : A -> A -> Prop) (Rwf : well_founded R)
          (P : forall a b c d e f g h i j, K a b c d e f g h i j -> Type).

  Local Notation Fix10 := (@Fix A R Rwf (fun a : A => forall b c d e f g h i j k, @P a b c d e f g h i j k)).
  Local Notation T := (fun a => tele _ (fun b => tele _ (fun c => tele _ (fun d => tele _ (fun e => tele _ (fun f => tele _ (fun g => tele _ (fun h => tele _ (fun i => tele _ (fun j => tele _ (fun _ : @K a b c d e f g h i j => bottom))))))))))).

  Let Fix10_eq' := @FixV_eq A T R Rwf P.
  Let Fix10_eq'T := Eval simpl in type_of Fix10_eq'.

  Let Fix10_rect' := @FixV_rect A T R Rwf P.
  Let Fix10_rect'T := Eval simpl in type_of Fix10_rect'.

  Let Fix10_Proper_eq' := @FixV_Proper_eq A T R Rwf P.
  Let Fix10_Proper_eq'T := Eval simpl in type_of Fix10_Proper_eq'.

  Let Fix10_Proper_eq_with_assumption' := @FixV_Proper_eq_with_assumption A T R Rwf P.
  Let Fix10_Proper_eq_with_assumption'T := Eval simpl in type_of Fix10_Proper_eq_with_assumption'.

  Definition Fix10_eq : Fix10_eq'T := Fix10_eq'.
  Definition Fix10_rect : Fix10_rect'T := Fix10_rect'.
  Definition Fix10_Proper_eq : Fix10_Proper_eq'T := Fix10_Proper_eq'.
  Definition Fix10_Proper_eq_with_assumption : Fix10_Proper_eq_with_assumption'T := Fix10_Proper_eq_with_assumption'.
End Fix10.

Arguments Fix10_Proper_eq {A B C D E F G H I J K R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _ _ _.
Arguments Fix10_Proper_eq_with_assumption {A B C D E F G H I J K R Rwf P} _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _.
Global Existing Instance Fix10_Proper_eq.
Global Existing Instance Fix10_Proper_eq_with_assumption.
