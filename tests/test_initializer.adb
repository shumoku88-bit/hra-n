------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Initializer
-------------------------------------------------------------------------------

with Ada.Directories;
with Test_Support;                   use Test_Support;
with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Validity;            use HRA_N.Core.Validity;
with HRA_N.Application.Initializer;  use HRA_N.Application.Initializer;
with HRA_N.Application.Doctor;       use HRA_N.Application.Doctor;
with HRA_N.Application.Publisher;    use HRA_N.Application.Publisher;

package body Test_Initializer is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_init";
      J_Path   : constant String := Test_Dir & "/journal.hra";
      P_Path   : constant String := Test_Dir & "/policy.hra";
      S_Path   : constant String := Test_Dir & "/scheduled.hra";
   begin
      --  Clean previous artifacts if any
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;

      --  1. Fresh initialization
      declare
         Res : constant Init_Result := Initialize_Household (Test_Dir);
      begin
         Assert (Res.Success, "Fresh household initialization succeeds");
         Assert (Ada.Directories.Exists (J_Path), "journal.hra created");
         Assert (Ada.Directories.Exists (P_Path), "policy.hra created");
         Assert (Ada.Directories.Exists (S_Path), "scheduled.hra created");
      end;

      --  2. Doctor health audit on fresh household
      declare
         Report : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => Test_Dir,
            Coverage_Path => "",
            Report        => Report,
            Quiet         => True);

         Assert (Report.Overall_Healthy, "Newly initialized household is 100% healthy");
         Assert_Equal_Int (0, Long_Long_Integer (Report.Total_Events), "Fresh household has 0 events");
         Assert_Equal_Int (3, Long_Long_Integer (Report.Total_Loci), "Fresh household has 3 roles from initial policy");
         Assert_Equal_Int (2, Long_Long_Integer (Report.Total_Coverage), "Fresh household has 2 zero-origin coords");
      end;

      --  3. Idempotency & safety check: Refuse to overwrite existing authority
      declare
         Res2 : constant Init_Result := Initialize_Household (Test_Dir);
      begin
         Assert (not Res2.Success, "Initializer safely refuses to overwrite existing authority");
      end;

      --  4. Record first transaction in newly initialized household
      declare
         Pub_Res : constant Publish_Result :=
           Publish_Movement
             (Journal_Path => J_Path,
              Policy_Path  => P_Path,
              From_Locus   => "cash",
              To_Locus     => "food",
              Amount       => 800,
              Valid_On     => (Year => 2026, Month => 9, Day => 4),
              Description  => "Initial test grocery");
      begin
         Assert (Pub_Res.Success, "Publishing first movement in initialized household succeeds");
      end;

      --  Clean up
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
   end Run;

end Test_Initializer;
