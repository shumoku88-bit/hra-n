------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Initializer
-------------------------------------------------------------------------------

with Ada.Directories;
with Test_Support;                   use Test_Support;
with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Validity;            use HRA_N.Core.Validity;
with HRA_N.Application.Initializer;  use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Doctor;       use HRA_N.Application.Doctor;
with HRA_N.Core.Event;               use HRA_N.Core.Event;
with HRA_N.Storage.Journal_Writer;  use HRA_N.Storage.Journal_Writer;

package body Test_Initializer is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_init";
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
         declare
            Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         begin
            Assert (Paths.Resolution_Ok, "Initial snapshot resolves");
            Assert (Paths.Is_Versioned, "Initial snapshot is versioned");
            Assert (Snapshot_Id_Str (Paths) = "g00000001", "Initial snapshot identity is stable");
            Assert (Ada.Directories.Exists (Journal_Path_Str (Paths)), "journal.hra created");
            Assert (Ada.Directories.Exists (Policy_Path_Str (Paths)), "policy.hra created");
            Assert (Ada.Directories.Exists (Scheduled_Path_Str (Paths)), "scheduled.hra created");
            Assert (Ada.Directories.Exists (Test_Dir & "/.hra/CURRENT"), "CURRENT selector created");
         end;
      end;

      --  2. Doctor health audit on fresh household
      declare
         Report : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => Test_Dir,
            Report        => Report,
            Quiet         => True);

         Assert (Report.Overall_Healthy, "Newly initialized household is 100% healthy");
         Assert_Equal_Int (0, Long_Long_Integer (Report.Total_Events), "Fresh household has 0 events");
         Assert_Equal_Int (5, Long_Long_Integer (Report.Total_Loci), "Fresh household has 5 role assignments");
         Assert_Equal_Int (2, Long_Long_Integer (Report.Total_Coverage), "Fresh household has 2 zero-origin coords");
      end;

      --  3. Idempotency & safety check: Refuse to overwrite existing authority
      declare
         Res2 : constant Init_Result := Initialize_Household (Test_Dir);
      begin
         Assert (not Res2.Success, "Initializer safely refuses to overwrite existing authority");
      end;

      --  4. A selected generation is immutable; direct appends are rejected
      --  and all writes go through the generation transaction.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Effs  : Effect_List;
         JPY   : constant Measure_Id := (Token => Make_Token ("jpy"));
         App_Res : Append_Result;
      begin
         Effs.Count := 2;
         Effs.Values (1) :=
           (Key     => (Token => Make_Token ("0")),
            Locus   => (Token => Make_Token ("cash")),
            Measure => JPY,
            Amount  => (Quanta => -800));
         Effs.Values (2) :=
           (Key     => (Token => Make_Token ("1")),
            Locus   => (Token => Make_Token ("food")),
            Measure => JPY,
            Amount  => (Quanta => 800));
         App_Res := Append_Transaction
           (Journal_Path => Journal_Path_Str (Paths),
            Tx_Id        => "e9999",
            Valid_On     => (Year => 2026, Month => 9, Day => 4),
            Effects      => Effs,
            Description  => "Initial test grocery");
         Assert (not App_Res.Success, "Direct mutation of selected generation is rejected");
      end;

      --  Clean up
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
   end Run;

end Test_Initializer;
