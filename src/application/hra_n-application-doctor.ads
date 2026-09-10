-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Doctor
--
--  Comprehensive diagnostic inspection and self-healing verification.
--  Audits cryptographic SHA-256 integrity, zero-sum conservation laws,
--  event identity nodup invariants, referential validity across families,
--  locus admission bounds, relation provenance syntax, and zero-origin
--  coverage consistency.
-------------------------------------------------------------------------------

package HRA_N.Application.Doctor is

   type Diagnostic_Item is record
      Passed  : Boolean           := False;
      Summary : String (1 .. 64)  := [others => ' '];
      Sum_Len : Natural           := 0;
      Detail  : String (1 .. 128) := [others => ' '];
      Det_Len : Natural           := 0;
   end record;

   type Doctor_Report is record
      Manifest_Check     : Diagnostic_Item;
      Crypto_Check       : Diagnostic_Item;
      Conservation_Check : Diagnostic_Item;
      Validity_Check     : Diagnostic_Item;
      Description_Check  : Diagnostic_Item;
      Admission_Check    : Diagnostic_Item;
      Coverage_Check     : Diagnostic_Item;
      Relation_Check     : Diagnostic_Item;

      Total_Events       : Natural := 0;
      Total_Validity     : Natural := 0;
      Total_Descriptions : Natural := 0;
      Total_Loci         : Natural := 0;
      Total_Coverage     : Natural := 0;
      Total_Relations    : Natural := 0;
      Total_Discharges   : Natural := 0;

      Overall_Healthy    : Boolean := False;
   end record;

   --  Run all diagnostics against the given authority and coverage paths.
   --  If Quiet is False, prints a structured terminal diagnostic report.
   procedure Run_Doctor
     (Authority_Dir : String;
      Coverage_Path : String;
      Report        : out Doctor_Report;
      Quiet         : Boolean := False);

end HRA_N.Application.Doctor;
