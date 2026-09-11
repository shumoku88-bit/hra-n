with Ada.Directories;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with Test_Support; use Test_Support;

package body Test_Movement_Command is
   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_movement_command";
      Intent : constant Movement_Intent :=
        (From_Locus => (Token => Make_Token ("cash")),
         To_Locus   => (Token => Make_Token ("food")),
         Measure    => (Token => Make_Token ("jpy")),
         Amount     => 1_250,
         Valid_On   => Make_Date (2026, 9, 14),
         Description => Make_Token ("Lunch"));
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Assert (Initialize_Household (Test_Dir).Success,
              "Movement command fixture initializes");

      declare
         Invalid : Movement_Intent := Intent;
      begin
         Invalid.Description := Make_Token ("bad""description");
         Assert (not Propose (Resolve_Paths (Test_Dir), Invalid).Success,
                 "Unencodable description fails before proposal creation");
      end;

      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Proposed : constant Proposal_Result := Propose (Paths, Intent);
      begin
         Assert (Proposed.Success, "Typed movement intent produces proposal");
         Assert (Expected_Snapshot (Proposed.Proposal) = "g00000001",
                 "Proposal binds selected snapshot");
         Assert (Proposed_Event_Id (Proposed.Proposal) = "e0001",
                 "Proposal exposes deterministic event identity");
         declare
            Receipt : constant Movement_Receipt := Commit (Proposed.Proposal);
            Retried : constant Movement_Receipt := Commit (Proposed.Proposal);
         begin
            Assert (Receipt.Success, "Movement proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000002",
                    "Receipt identifies activated snapshot");
            Assert (Retried.Success, "Movement proposal retry is idempotent");
            Assert (Retried.Snapshot_Id (1 .. Retried.Snapshot_Len) = "g00000002",
                    "Retry recovers the same receipt");
            Assert (not Ada.Directories.Exists
                      (Test_Dir & "/.hra/generations/g00000003"),
                    "Movement retry does not create another generation");
         end;
      end;

      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         First : constant Proposal_Result := Propose (Paths, Intent);
         Other_Intent : Movement_Intent := Intent;
      begin
         Other_Intent.Amount := 900;
         declare
            Second : constant Proposal_Result := Propose (Paths, Other_Intent);
            First_Receipt : constant Movement_Receipt := Commit (First.Proposal);
            Stale_Receipt : constant Movement_Receipt := Commit (Second.Proposal);
         begin
            Assert (First.Success and then Second.Success,
                    "Concurrent intents can be proposed from one snapshot");
            Assert (First_Receipt.Success, "First proposed movement commits");
            Assert (not Stale_Receipt.Success,
                    "Different proposal from stale snapshot is rejected");
         end;
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;
end Test_Movement_Command;
