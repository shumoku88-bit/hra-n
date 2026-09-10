with Ada.Text_IO;               use Ada.Text_IO;
with Test_Support;              use Test_Support;
with HRA_N.Application.Doctor;  use HRA_N.Application.Doctor;

package body Test_Doctor is

   procedure Run is
      Auth_Dir : constant String := Real_Data_Dir & "/movement-authority";
      Cov_Path : constant String := Real_Data_Dir & "/zero-origin-coverage.loam";
      Report   : Doctor_Report;
   begin
      if not Real_Data_Available then
         Put_Line ("    [SKIP] Real authority not present (standalone CI mode)");
         return;
      end if;

      --  1. Real authority full health check (verbose to see diagnostics)
      Run_Doctor
        (Authority_Dir => Auth_Dir,
         Coverage_Path => Cov_Path,
         Report        => Report,
         Quiet         => False);

      Assert (Report.Overall_Healthy, "Real authority passes overall health audit");
      Assert (Report.Manifest_Check.Passed, "Manifest check passes");
      Assert (Report.Crypto_Check.Passed, "Cryptographic SHA-256 integrity passes");
      Assert (Report.Conservation_Check.Passed, "Event conservation laws hold (sum = 0)");
      Assert (Report.Validity_Check.Passed, "ActualValidity referential integrity holds");
      Assert (Report.Description_Check.Passed, "EventDescription integrity holds");
      Assert (Report.Admission_Check.Passed, "LocusAdmission compliance holds");
      Assert (Report.Coverage_Check.Passed, "Zero-origin coverage evidence holds");
      Assert (Report.Relation_Check.Passed, "Relation provenance syntax holds");

      Assert_Equal_Int (588, Long_Long_Integer (Report.Total_Events), "Audited exact 588 events");
      Assert_Equal_Int (588, Long_Long_Integer (Report.Total_Validity), "Audited exact 588 validity facts");
      Assert_Equal_Int (588, Long_Long_Integer (Report.Total_Descriptions), "Audited exact 588 descriptions");
      Assert_Equal_Int (26, Long_Long_Integer (Report.Total_Loci), "Audited exact 26 admitted loci");
      Assert_Equal_Int (5, Long_Long_Integer (Report.Total_Coverage), "Audited exact 5 covered coordinates");
      Assert_Equal_Int (0, Long_Long_Integer (Report.Total_Relations), "Audited empty relation unit memory");
      Assert_Equal_Int (0, Long_Long_Integer (Report.Total_Discharges), "Audited empty relation discharge memory");

      --  2. Non-existent path fail-closed check
      declare
         Bad_Report : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => "/non/existent/path",
            Coverage_Path => Cov_Path,
            Report        => Bad_Report,
            Quiet         => True);

         Assert (not Bad_Report.Overall_Healthy, "Non-existent authority fails overall health audit");
         Assert (not Bad_Report.Manifest_Check.Passed, "Non-existent manifest check fails closed");
      end;
   end Run;

end Test_Doctor;
