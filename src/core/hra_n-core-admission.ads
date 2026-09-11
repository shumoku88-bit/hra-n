-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Admission
--
--  Explicit Locus Admission Vocabulary (Loam Observation 212).
--  Every new movement effect must target an approved locus coordinate.
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Admission with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Admitted_Loci : constant := 128;

   subtype Locus_Count_Type is Natural range 0 .. Max_Admitted_Loci;
   subtype Locus_Index_Type is Positive range 1 .. Max_Admitted_Loci;

   type Locus_Array is array (Locus_Index_Type) of Locus_Id;

   type Locus_Vocabulary is record
      Count  : Locus_Count_Type := 0;
      Values : Locus_Array      := [others =>
                 (Token => (Length => 0, Value => [others => ' ']))];
   end record;

   function Loci_Are_Unique (Vocab : Locus_Vocabulary) return Boolean;

   --  Predicate checking if a Locus is affirmatively admitted for new recording.
   function Admits_Locus
     (Vocab : Locus_Vocabulary;
      Locus : Locus_Id) return Boolean is
     (for some I in 1 .. Vocab.Count =>
        Equal_Token (Vocab.Values (I).Token, Locus.Token));

   function Admits_Effects
     (Vocab   : Locus_Vocabulary;
      Effects : Effect_List) return Boolean is
     (for all I in 1 .. Effects.Count =>
        Admits_Locus (Vocab, Effects.Values (I).Locus));

   function Make_Vocabulary
     (Loci  : Locus_Array;
      Count : Locus_Count_Type) return Locus_Vocabulary;

end HRA_N.Core.Admission;
