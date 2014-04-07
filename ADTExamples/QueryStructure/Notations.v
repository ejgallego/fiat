Reserved Infix ":"
         (no associativity, at level 60).

Reserved Notation "t ! r"
         (no associativity, at level 0).

Reserved Notation "< col1 , .. , coln >"
         (at level 0, col1, coln at level 60,
          format "< '[v  ' col1 ,  .. ,  coln ']' >").

(* Class used to overload equality test notation (==) in queries. *)
Class Query_eq (A : Type) :=
      {A_eq_dec : forall a a' : A, {a = a'} + {a <> a'}}.

Infix "==" := (A_eq_dec) (at level 1).

Reserved Notation "'attributes' attrlist1 'depend' 'on' attrlist2 "
         (at level 50).

Reserved Notation "'attribute' attr 'of' rel1 'references' rel2 "
         (at level 50).

Reserved Notation "'relation' name 'has' sch"
  (at level 0, name at level 8, schema at level 0).

Reserved Notation "'schema' headings"
  (at level 0, headings at level 0, constraints at level 50).

Reserved Notation "'schema' headings 'where' constraints"
  (at level 0, headings at level 0, constraints at level 50).

Reserved Notation "'query' 'structure' 'schema' relList "
         (at level 0).

Reserved Notation "'query' 'structure' 'schema' relList 'enforcing' constraints"
         (at level 0, constraints at level 50).

Reserved Notation "( x 'in' r ) bod"
         (right associativity, at level 0,
          format "( x  'in'  r ) '//' bod ").

Reserved Notation "'Return' t"
         (right associativity, at level 0,
          format "'Return'  t" ).

Reserved Notation "'Where' p bod"
         (right associativity, at level 0, x at level 0, p at level 0,
          format "'Where'  p '//' bod " ).

Reserved Notation "'For' bod"
         (right associativity, at level 0,
          format "'For'  '[v' bod ']'").

Delimit Scope Attribute_scope with Attribute.
Delimit Scope Heading_scope with Heading.
Delimit Scope Component_scope with Component.
Delimit Scope Tuple_scope with Tuple.
Delimit Scope Relation_scope with Relation.
Delimit Scope SchemaConstraints_scope with SchemaConstraints.
Delimit Scope Schema_scope with Schema.
Delimit Scope NamedSchema_scope with NamedSchema.
Delimit Scope QSSchema_scope with QSSchema.
Delimit Scope QSSchemaConstraints_scope with QSSchemaConstraints.
Delimit Scope QuerySpec_scope with QuerySpec.
Delimit Scope QueryStructure_scope with QueryStructure.
