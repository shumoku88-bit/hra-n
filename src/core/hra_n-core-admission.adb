-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Admission
-------------------------------------------------------------------------------

package body HRA_N.Core.Admission with
  SPARK_Mode => On
is

   function Make_Vocabulary
     (Loci  : Locus_Array;
      Count : Locus_Count_Type) return Locus_Vocabulary
   is
   begin
      return (Count => Count, Values => Loci);
   end Make_Vocabulary;

end HRA_N.Core.Admission;
