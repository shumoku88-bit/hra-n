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
      Auth_Dir : constant String := Test_Dir & "/movement-authority";
      Cov_Path : constant String := Test_Dir & "/zero-origin-coverage.loam";
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
         Assert (Ada.Directories.Exists (Auth_Dir & "/CURRENT"), "CURRENT manifest created");
         Assert (Ada.Directories.Exists (Cov_Path), "zero-origin-coverage.loam created");
      end;

      --  2. Doctor health audit on fresh household
      declare
         Report : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => Auth_Dir,
            Coverage_Path => Cov_Path,
            Report        => Report,
            Quiet         => True);

         Assert (Report.Overall_Healthy, "Newly initialized household is 100% healthy");
         Assert_Equal_Int (0, Long_Long_Integer (Report.Total_Events), "Fresh household has 0 events");
         Assert_Equal_Int (7, Long_Long_Integer (Report.Total_Loci), "Fresh household has 7 default loci");
         Assert_Equal_Int (2, Long_Long_Integer (Report.Total_Coverage), "Fresh household has 2 covered loci");
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
             (Authority_Dir => Auth_Dir,
              From_Locus    => "cash",
              To_Locus      => "food",
              Amount        => 800,
              Valid_On      => Make_Date (2026, 9, 10),
              Description   => "Initial grocery purchase");
      begin
         Assert (Pub_Res.Success, "First movement publication succeeds");
         Assert (Pub_Res.Event_Id_Len > 0, "Allocated fresh EventId");
      end;

      --  5. Verify health after first transaction
      declare
         Report2 : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => Auth_Dir,
            Coverage_Path => Cov_Path,
            Report        => Report2,
            Quiet         => True);

         Assert (Report2.Overall_Healthy, "Household remains 100% healthy after first publication");
         Assert_Equal_Int (1, Long_Long_Integer (Report2.Total_Events), "Event count increased to 1");
         Assert_Equal_Int (1, Long_Long_Integer (Report2.Total_Validity), "Validity count increased to 1");
         Assert_Equal_Int (1, Long_Long_Integer (Report2.Total_Descriptions), "Description count increased to 1");
      end;

      --  Clean up test directory
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
   end Run;

end Test_Initializer;
