with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Generation_Transaction; use HRA_N.Storage.Generation_Transaction;

package body Test_Generation_Transaction is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_generation_transaction";
      Policy : constant String :=
        "# HRA-N Household Policy" & ASCII.LF &
        "ROLE cash, bank: ASSET" & ASCII.LF &
        "ROLE food, misc: EXPENSE" & ASCII.LF &
        "ROLE salary: INCOME" & ASCII.LF &
        "ZERO-ORIGIN cash, bank" & ASCII.LF;
      Scheduled : constant String :=
        "# HRA-N Scheduled Journal" & ASCII.LF &
        "# Facts: SCHED, COMPLETE, RETIRE, REPLACE" & ASCII.LF;
      Initial_Journal : constant String :=
        "# HRA-N Canonical Journal" & ASCII.LF &
        "# Format: TX <id> <date> <flows...> [tags...] [""description""]" & ASCII.LF;
      First_Journal : constant String :=
        Initial_Journal &
        "TX e0001 2026-09-11 cash:-100 food:100 ""Lunch""" & ASCII.LF;
      Second_Journal : constant String :=
        First_Journal &
        "TX e0002 2026-09-12 cash:-50 food:50" & ASCII.LF;
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;

      Assert (Initialize_Household (Test_Dir).Success,
              "Generation transaction fixture initializes");

      declare
         Committed : constant Commit_Result :=
           Commit
             (Base_Dir          => Test_Dir,
              Expected_Snapshot => "g00000001",
              Journal_Content   => First_Journal,
              Policy_Content    => Policy,
              Scheduled_Content => Scheduled);
      begin
         Assert (Committed.Success, "Complete balanced candidate commits");
         Assert (Committed.Snapshot_Id (1 .. Committed.Snapshot_Len) = "g00000002",
                 "Commit allocates next generation identity");
      end;

      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
      begin
         Assert (Paths.Resolution_Ok, "Committed generation resolves");
         Assert (Snapshot_Id_Str (Paths) = "g00000002", "CURRENT selects committed generation");
         Assert (Ada.Directories.Exists (Journal_Path_Str (Paths)),
                 "Committed journal exists in selected generation");
      end;

      declare
         Stale : constant Commit_Result :=
           Commit
             (Base_Dir          => Test_Dir,
              Expected_Snapshot => "g00000001",
              Journal_Content   => "# stale" & ASCII.LF,
              Policy_Content    => Policy,
              Scheduled_Content => Scheduled);
      begin
         Assert (not Stale.Success, "Stale expected snapshot is rejected under lock");
         Assert (Snapshot_Id_Str (Resolve_Paths (Test_Dir)) = "g00000002",
                 "Stale rejection preserves selected generation");
      end;

      declare
         Invalid : constant Commit_Result :=
           Commit
             (Base_Dir          => Test_Dir,
              Expected_Snapshot => "g00000002",
              Journal_Content   => First_Journal &
                "TX e0002 2026-09-11 cash:-100 food:90" & ASCII.LF,
              Policy_Content    => Policy,
              Scheduled_Content => Scheduled);
      begin
         Assert (not Invalid.Success, "Unbalanced candidate fails complete admission");
         Assert (Snapshot_Id_Str (Resolve_Paths (Test_Dir)) = "g00000002",
                 "Admission rejection preserves selected generation");
         Assert (not Ada.Directories.Exists
                   (Test_Dir & "/.hra/generations/g00000003"),
                 "Rejected candidate generation is removed");
      end;

      declare
         Rewritten : constant Commit_Result :=
           Commit
             (Test_Dir, "g00000002", Initial_Journal, Policy, Scheduled);
      begin
         Assert (not Rewritten.Success,
                 "Candidate cannot remove an admitted journal transaction");
         Assert (Snapshot_Id_Str (Resolve_Paths (Test_Dir)) = "g00000002",
                 "Append-only rejection preserves selected generation");
      end;

      declare
         Policy_Mutation : constant Commit_Result :=
           Commit
             (Test_Dir, "g00000002", First_Journal,
              Policy & "# mutation" & ASCII.LF, Scheduled);
         Scheduled_Rewrite : constant Commit_Result :=
           Commit
             (Test_Dir, "g00000002", First_Journal,
              Policy, "# rewritten scheduled state" & ASCII.LF);
      begin
         Assert (not Policy_Mutation.Success,
                 "Versioned policy is immutable without policy facts");
         Assert (not Scheduled_Rewrite.Success,
                 "Candidate cannot rewrite scheduled history");
      end;

      for Fault in After_Lock .. After_Admission loop
         declare
            Interrupted : constant Commit_Result :=
              Commit
                (Test_Dir, "g00000002",
                 Second_Journal, Policy, Scheduled, Fault);
         begin
            Assert (not Interrupted.Success,
                    "Injected pre-activation failure returns no receipt");
            Assert (Snapshot_Id_Str (Resolve_Paths (Test_Dir)) = "g00000002",
                    "Pre-activation failure preserves old authority");
         end;
      end loop;

      declare
         Interrupted : constant Commit_Result :=
           Commit
             (Test_Dir, "g00000002",
              Second_Journal, Policy, Scheduled, After_Activation);
      begin
         Assert (not Interrupted.Success,
                 "Injected post-activation failure returns no receipt");
         Assert (Snapshot_Id_Str (Resolve_Paths (Test_Dir)) = "g00000003",
                 "Post-activation failure exposes only the complete new authority");
      end;

      declare
         Recovered : constant Commit_Result :=
           Commit
             (Test_Dir, "g00000002",
              Second_Journal, Policy, Scheduled);
      begin
         Assert (Recovered.Success,
                 "Retry recovers receipt from the already selected candidate");
         Assert (Recovered.Snapshot_Id (1 .. Recovered.Snapshot_Len) = "g00000003",
                 "Recovered receipt identifies durable selected generation");
         Assert (not Ada.Directories.Exists
                   (Test_Dir & "/.hra/generations/g00000004"),
                 "Idempotent retry does not allocate another generation");
      end;

      Ada.Directories.Delete_Tree (Test_Dir);

      --  Two writers may prepare from one snapshot, but only the writer that
      --  owns the lock before activation may publish it.
      declare
         Concurrent_Dir : constant String :=
           "/tmp/hra_n_test_generation_transaction_concurrent";
      begin
         if Ada.Directories.Exists (Concurrent_Dir) then
            Ada.Directories.Delete_Tree (Concurrent_Dir);
         end if;
         Assert (Initialize_Household (Concurrent_Dir).Success,
                 "Concurrent transaction fixture initializes");
         declare
            First_Result  : Commit_Result;
            Second_Result : Commit_Result;
            task First_Writer
              with Storage_Size => 16 * 1024 * 1024
            is
               entry Start;
               entry Wait;
            end First_Writer;
            task Second_Writer
              with Storage_Size => 16 * 1024 * 1024
            is
               entry Start;
               entry Wait;
            end Second_Writer;
            task body First_Writer is
            begin
               accept Start;
               First_Result := Commit
                 (Concurrent_Dir, "g00000001",
                  Initial_Journal &
                    "TX e0001 2026-09-11 cash:-100 food:100" & ASCII.LF,
                  Policy, Scheduled);
               accept Wait;
            end First_Writer;
            task body Second_Writer is
            begin
               accept Start;
               Second_Result := Commit
                 (Concurrent_Dir, "g00000001",
                  Initial_Journal &
                    "TX e0001 2026-09-11 cash:-200 food:200" & ASCII.LF,
                  Policy, Scheduled);
               accept Wait;
            end Second_Writer;
         begin
            First_Writer.Start;
            Second_Writer.Start;
            First_Writer.Wait;
            Second_Writer.Wait;
            Assert (First_Result.Success xor Second_Result.Success,
                    "Exactly one concurrent writer succeeds");
         end;
         Assert (Snapshot_Id_Str (Resolve_Paths (Concurrent_Dir)) = "g00000002",
                 "Concurrent writers activate exactly one next generation");
         Assert (not Ada.Directories.Exists
                   (Concurrent_Dir & "/.hra/generations/g00000003"),
                 "Stale concurrent writer does not allocate after lock");
         Ada.Directories.Delete_Tree (Concurrent_Dir);
      end;
   end Run;

end Test_Generation_Transaction;
