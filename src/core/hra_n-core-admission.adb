-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Admission
-------------------------------------------------------------------------------

package body HRA_N.Core.Admission with
  SPARK_Mode => On
is

   function Loci_Are_Unique (Vocab : Locus_Vocabulary) return Boolean is
   begin
      for I in 1 .. Vocab.Count loop
         for J in I + 1 .. Vocab.Count loop
            if Equal_Token
              (Vocab.Values (I).Token, Vocab.Values (J).Token)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Loci_Are_Unique;

   function Make_Vocabulary
     (Loci  : Locus_Array;
      Count : Locus_Count_Type) return Locus_Vocabulary
   is
   begin
      return (Count => Count, Values => Loci);
   end Make_Vocabulary;

end HRA_N.Core.Admission;
