-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Locus Admission & Reader Implementation
-------------------------------------------------------------------------------

with HRA_N.Core.Types;          use HRA_N.Core.Types;
with HRA_N.Core.Admission;      use HRA_N.Core.Admission;
with HRA_N.Storage.Locus_Reader; use HRA_N.Storage.Locus_Reader;
with Test_Support;              use Test_Support;

package body Test_Admission is

   procedure Run is
      Loci  : Locus_Array := [others => (Token => (Length => 0, Value => [others => ' ']))];
      Vocab : Locus_Vocabulary;
   begin
      --  1. In-memory core admission test
      Loci (1) := (Token => Make_Token ("cash"));
      Loci (2) := (Token => Make_Token ("smbc"));
      Vocab := Make_Vocabulary (Loci, 2);

      Assert (Admits_Locus (Vocab, (Token => Make_Token ("cash"))), "Admits 'cash'");
      Assert (Admits_Locus (Vocab, (Token => Make_Token ("smbc"))), "Admits 'smbc'");
      Assert (not Admits_Locus (Vocab, (Token => Make_Token ("bitcoin"))), "Rejects unadmitted 'bitcoin'");

      --  2. Real LocusAdmission file loading
      if Real_Data_Available then
         declare
            Real_Path : constant String :=
              Real_Data_Dir & "/movement-authority/objects/LocusAdmission/" &
              "6b87f52830909a18102780375508d32b6323b3a23de32d882e3cd61a92905a3b.loam";
            Result : constant Read_Locus_Result := Read_Locus_File (Real_Path);
         begin
            Assert (Result.Success, "Real LocusAdmission file loads successfully");
            Assert (Result.Vocabulary.Count = 26, "Loaded exact 26 approved loci from real data");
            Assert (Admits_Locus (Result.Vocabulary, (Token => Make_Token ("paypay"))), "Real data admits 'paypay'");
            Assert (Admits_Locus (Result.Vocabulary, (Token => Make_Token ("tobacco"))), "Real data admits 'tobacco'");
            Assert (not Admits_Locus (Result.Vocabulary, (Token => Make_Token ("crypto"))), "Real data rejects unapproved 'crypto'");
         end;
      end if;
   end Run;

end Test_Admission;
