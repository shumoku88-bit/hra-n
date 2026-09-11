with Ada.Directories;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Relation_Command; use HRA_N.Application.Relation_Command;
with HRA_N.Application.Relation_Query; use HRA_N.Application.Relation_Query;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with Test_Support; use Test_Support;

package body Test_Relation_Command is

   function Shop_Endpoint return Relation_Endpoint is
     (External_Endpoint (Make_Token ("shop")));

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_relation_command";
      New_Claim : constant Raise_Claim_Intent :=
        (Source   => Make_Token ("e0001"),
         Debtor   => Household_Endpoint,
         Creditor => Shop_Endpoint,
         Measure  => Make_Token ("jpy"),
         Amount   => 3_000);
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Assert (Initialize_Household (Test_Dir).Success,
              "Relation fixture initializes");
      Append_Initial_Policy (Test_Dir, "LOCUS shop" & ASCII.LF);

      --  Two source and settlement events through the shared movement path.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         First : constant Movement_Intent :=
           (From_Locus  => (Token => Make_Token ("cash")),
            To_Locus    => (Token => Make_Token ("shop")),
            Measure     => (Token => Make_Token ("jpy")),
            Amount      => 3_000,
            Valid_On    => Make_Date (2026, 9, 1),
            Description => Make_Token ("Bike"));
         Second : Movement_Intent := First;
         First_R  : constant Movement_Receipt :=
           HRA_N.Application.Movement_Command.Commit (HRA_N.Application.Movement_Command.Propose (Paths, First).Proposal);
         Fresh    : constant Path_Config := Resolve_Paths (Test_Dir);
      begin
         Assert (First_R.Success, "Source movement commits");
         Second.To_Locus := (Token => Make_Token ("cash"));
         Second.From_Locus := (Token => Make_Token ("bank"));
         Second.Amount := 5_000;
         Assert (HRA_N.Application.Movement_Command.Commit (HRA_N.Application.Movement_Command.Propose (Fresh, Second).Proposal).Success,
                 "Settlement movement commits");
      end;

      --  Raise-claim intent commits through the generation transaction.
      declare
         Paths    : constant Path_Config := Resolve_Paths (Test_Dir);
         Proposed : constant HRA_N.Application.Relation_Command.Proposal_Result :=
           HRA_N.Application.Relation_Command.Propose_Raise_Claim (Paths, New_Claim);
      begin
         Assert (Proposed.Success, "Raise-claim intent produces proposal");
         Assert (HRA_N.Application.Relation_Command.Proposed_Claim_Id (Proposed.Proposal) = "rel0001",
                 "Raise proposal allocates next claim identity");
         Assert (HRA_N.Application.Relation_Command.Expected_Snapshot (Proposed.Proposal) = "g00000003",
                 "Raise proposal binds selected snapshot");
         declare
            Receipt : constant Relation_Receipt := HRA_N.Application.Relation_Command.Commit (Proposed.Proposal);
            Retried : constant Relation_Receipt := HRA_N.Application.Relation_Command.Commit (Proposed.Proposal);
         begin
            Assert (Receipt.Success, "Raise-claim proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000004",
                    "Raise receipt identifies activated snapshot");
            Assert (Retried.Success, "Raise proposal retry is idempotent");
            Assert (Retried.Snapshot_Id (1 .. Retried.Snapshot_Len) = "g00000004",
                    "Retry recovers the same receipt");
         end;
      end;

      --  The admitted snapshot retains the claim with its face, and the
      --  query exposes it with the shared endpoint labels.
      declare
         Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
         Journal : constant Journal_Result :=
           Read_Journal_File (Journal_Path_Str (Paths));
         View    : constant Relation_View := Execute (Paths);
      begin
         Assert (Journal.Success, "Raised authority snapshot stays admitted");
         Assert (Journal.Relations.Claim_Count = 1, "One claim retained");
         Assert (View.Success and then View.Count = 1,
                 "Query exposes one open claim");
         Assert (View.Rows (1).Remaining = 3_000,
                 "Undischarged face is fully remaining");
         Assert (Endpoint_Label (View.Rows (1).Debtor) = "household",
                 "Household endpoint keeps its shared label");
         Assert (Endpoint_Label (View.Rows (1).Creditor) = "shop",
                 "External endpoint keeps its shared label");
      end;

      --  Raise guards fail closed.
      declare
         Paths    : constant Path_Config := Resolve_Paths (Test_Dir);
         Absent   : Raise_Claim_Intent := New_Claim;
         SameEnds : Raise_Claim_Intent := New_Claim;
         External : Raise_Claim_Intent := New_Claim;
         Zero     : Raise_Claim_Intent := New_Claim;
      begin
         Absent.Source := Make_Token ("e9999");
         Assert (not HRA_N.Application.Relation_Command.Propose_Raise_Claim (Paths, Absent).Success,
                 "Raise on an absent source fails closed");
         SameEnds.Creditor := SameEnds.Debtor;
         Assert (not HRA_N.Application.Relation_Command.Propose_Raise_Claim (Paths, SameEnds).Success,
                 "Raise with identical endpoints fails closed");
         External.Debtor := Shop_Endpoint;
         Assert (not HRA_N.Application.Relation_Command.Propose_Raise_Claim (Paths, External).Success,
                 "Raise without the household fails closed");
         Zero.Amount := 0;
         Assert (not HRA_N.Application.Relation_Command.Propose_Raise_Claim (Paths, Zero).Success,
                 "Raise with zero face fails closed");
      end;

      --  Discharge commits against the open remainder; over-face, absent
      --  claim, and duplicate-pair discharges fail closed.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Pay   : constant Record_Discharge_Intent :=
           (Claim      => Make_Token ("rel0001"),
            Settlement => Make_Token ("e0002"),
            Amount     => 1_000);
         Prop : constant HRA_N.Application.Relation_Command.Proposal_Result := HRA_N.Application.Relation_Command.Propose_Discharge (Paths, Pay);
         Over   : Record_Discharge_Intent := Pay;
         Absent : Record_Discharge_Intent := Pay;
      begin
         Assert (Prop.Success, "Discharge intent produces proposal");
         Assert (HRA_N.Application.Relation_Command.Commit (Prop.Proposal).Success, "Discharge commits");
         declare
            Fresh_After : constant Path_Config := Resolve_Paths (Test_Dir);
         begin
            Over.Amount := 2_500;
            Assert (not HRA_N.Application.Relation_Command.Propose_Discharge (Fresh_After, Over).Success,
                    "Discharge above the remainder fails closed");
            Absent.Claim := Make_Token ("rel0009");
            Assert (not HRA_N.Application.Relation_Command.Propose_Discharge (Fresh_After, Absent).Success,
                    "Discharge of an absent claim fails closed");
         end;
         declare
            Fresh : constant Path_Config := Resolve_Paths (Test_Dir);
            Dup   : constant HRA_N.Application.Relation_Command.Proposal_Result := HRA_N.Application.Relation_Command.Propose_Discharge (Fresh, Pay);
            Dup_R : constant Relation_Receipt := HRA_N.Application.Relation_Command.Commit (Dup.Proposal);
            View  : constant Relation_View := Execute (Fresh);
         begin
            Assert (Dup.Success, "Duplicate-pair discharge still proposes");
            Assert (not Dup_R.Success,
                    "Duplicate-pair discharge fails closed at commit");
            Assert (View.Success and then View.Count = 1
                    and then View.Rows (1).Remaining = 2_000,
                    "Partial discharge leaves the exact remainder open");
         end;
      end;

      --  Reversal of a relation-referenced event is refused, while the
      --  claim stays visible from its source detail links.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Revoke : constant Reversal_Intent :=
           (Target_Id   => Make_Token ("e0001"),
            Valid_On    => Make_Date (2026, 9, 5),
            Description => Make_Token ("Void bike"));
         Second_Revoke : constant Reversal_Intent :=
           (Target_Id   => Make_Token ("e0002"),
            Valid_On    => Make_Date (2026, 9, 5),
            Description => Make_Token ("Void pay"));
      begin
         Assert (not HRA_N.Application.Movement_Command.Propose_Reversal (Paths, Revoke).Success,
                 "Reversal of a claim source fails closed");
         Assert (not HRA_N.Application.Movement_Command.Propose_Reversal (Paths, Second_Revoke).Success,
                 "Reversal of a settlement event fails closed");
      end;

      --  A stale discharge proposal is rejected after the authority moves.
      declare
         Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
         Stale_D : constant Record_Discharge_Intent :=
           (Claim      => Make_Token ("rel0001"),
            Settlement => Make_Token ("e0002"),
            Amount     => 500);
         Third : constant Movement_Intent :=
           (From_Locus  => (Token => Make_Token ("bank")),
            To_Locus    => (Token => Make_Token ("cash")),
            Measure     => (Token => Make_Token ("jpy")),
            Amount      => 100,
            Valid_On    => Make_Date (2026, 9, 6),
            Description => Make_Token ("Top-up"));
      begin
         --  e0002 already settles rel0001 once, so settle from a fresh
         --  event instead to keep the stale scenario well-formed.
         declare
            Fresh_Ev : constant Movement_Receipt :=
              HRA_N.Application.Movement_Command.Commit (HRA_N.Application.Movement_Command.Propose (Paths, Third).Proposal);
            Fresh    : constant Path_Config := Resolve_Paths (Test_Dir);
            Well_Formed : Record_Discharge_Intent := Stale_D;
            Stale_P : HRA_N.Application.Relation_Command.Proposal_Result;
            Advance : constant HRA_N.Application.Relation_Command.Proposal_Result :=
              Propose_Raise_Claim
                (Fresh,
                 (Source   => Make_Token ("e0003"),
                  Debtor   => Household_Endpoint,
                  Creditor => Shop_Endpoint,
                  Measure  => Make_Token ("jpy"),
                  Amount   => 700));
            Advance_R : Relation_Receipt;
            Stale_R   : Relation_Receipt;
         begin
            Assert (Fresh_Ev.Success, "Stale-scenario event commits");
            Well_Formed.Settlement := Make_Token ("e0003");
            Stale_P := HRA_N.Application.Relation_Command.Propose_Discharge (Fresh, Well_Formed);
            Assert (Stale_P.Success, "Stale-scenario discharge proposes cleanly");
            Advance_R := HRA_N.Application.Relation_Command.Commit (Advance.Proposal);
            Assert (Advance_R.Success, "Advancing claim commits");
            Stale_R := HRA_N.Application.Relation_Command.Commit (Stale_P.Proposal);
            Assert (not Stale_R.Success,
                    "Discharge proposal from stale snapshot is rejected");
         end;
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;
end Test_Relation_Command;
