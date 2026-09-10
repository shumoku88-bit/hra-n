-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Doctor
--
--  Reads the three current household files and reports syntax, conservation,
--  policy, coverage, and scheduled-lifecycle health.
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

   --  Run diagnostics against the given household directory. If Quiet is
   --  False, print a structured terminal report.
   procedure Run_Doctor
     (Authority_Dir : String;
      Report        : out Doctor_Report;
      Quiet         : Boolean := False);

end HRA_N.Application.Doctor;
