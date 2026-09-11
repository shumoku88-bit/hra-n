with Ada.Directories;
with HRA_N.Application.Attention_Command; use HRA_N.Application.Attention_Command;
with HRA_N.Application.Attention_Query; use HRA_N.Application.Attention_Query;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with Test_Support; use Test_Support;

package body Test_Attention_Command is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_attention_command";
      Raise_Dated : constant Raise_Intent :=
        (Context => Make_Description ("Renew fire insurance"),
         Due     => (Kind => Due_On_Date,
                     Due_Date => Make_Date (2026, 10, 1)));
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Assert (Initialize_Household (Test_Dir).Success,
              "Attention fixture initializes");

      --  Empty authority carries no matters.
      declare
         View : constant Attention_View :=
           Execute (Resolve_Paths (Test_Dir));
      begin
         Assert (View.Success, "Empty attention query succeeds");
         Assert (View.Count = 0, "Empty query reports no open items");
      end;

      --  Raise intent commits through the generation transaction.
      declare
         Paths    : constant Path_Config := Resolve_Paths (Test_Dir);
         Proposed : constant Proposal_Result :=
           Propose_Raise (Paths, Raise_Dated);
      begin
         Assert (Proposed.Success, "Raise intent produces proposal");
         Assert (Proposed_Item_Id (Proposed.Proposal) = "att0001",
                 "Raise proposal allocates next item identity");
         Assert (Expected_Snapshot (Proposed.Proposal) = "g00000001",
                 "Raise proposal binds selected snapshot");
         declare
            Receipt : constant Attention_Receipt := Commit (Proposed.Proposal);
            Retried : constant Attention_Receipt := Commit (Proposed.Proposal);
         begin
            Assert (Receipt.Success, "Raise proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000002",
                    "Raise receipt identifies activated snapshot");
            Assert (Retried.Success, "Raise proposal retry is idempotent");
            Assert (Retried.Snapshot_Id (1 .. Retried.Snapshot_Len) = "g00000002",
                    "Retry recovers the same receipt");
         end;
      end;

      --  The admitted snapshot retains the item with its due meaning, and
      --  the query exposes it with the shared label.
      declare
         Paths  : constant Path_Config := Resolve_Paths (Test_Dir);
         Policy : constant Policy_Result :=
           Read_Policy_File (Policy_Path_Str (Paths));
         View   : constant Attention_View := Execute (Paths);
      begin
         Assert (Policy.Success, "Raised authority snapshot stays admitted");
         Assert (Policy.Attention.Item_Count = 1, "One attention item retained");
         Assert (Is_Open (Policy.Attention, Make_Token ("att0001")),
                 "Raised item is open");
         Assert (View.Success and then View.Count = 1,
                 "Query exposes one open item");
         Assert (Due_Label (View.Rows (1).Due) = "due 2026-10-01",
                 "Dated due keeps its shared label");
      end;

      --  Raise guards fail closed.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Empty_Ctx : Raise_Intent := Raise_Dated;
         Quoted    : Raise_Intent := Raise_Dated;
         Bad_Due   : Raise_Intent := Raise_Dated;
      begin
         Empty_Ctx.Context := Make_Description ("");
         Assert (not Propose_Raise (Paths, Empty_Ctx).Success,
                 "Raise with empty context fails closed");
         Quoted.Context := Make_Description ("say ""hi""");
         Assert (not Propose_Raise (Paths, Quoted).Success,
                 "Raise with quote in context fails closed");
         Bad_Due.Due :=
           (Kind => Due_On_Date,
            Due_Date => (Year => 2026, Month => 2, Day => 30));
         Assert (not Propose_Raise (Paths, Bad_Due).Success,
                 "Raise with impossible due date fails closed");
      end;

      --  Close intent retires the item; a second close fails closed.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Close : constant Close_Intent :=
           (Target_Id => Make_Token ("att0001"),
            Kind      => Closure_Resolved,
            Known_On  => Make_Date (2026, 9, 20));
         Prop : constant Proposal_Result := Propose_Close (Paths, Close);
         Absent : constant Close_Intent :=
           (Target_Id => Make_Token ("att9999"),
            Kind      => Closure_Resolved,
            Known_On  => Make_Date (2026, 9, 20));
      begin
         Assert (Prop.Success, "Close intent produces proposal");
         Assert (not Propose_Close (Paths, Absent).Success,
                 "Close of an absent item fails closed");
         declare
            Receipt : constant Attention_Receipt := Commit (Prop.Proposal);
         begin
            Assert (Receipt.Success, "Close proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000003",
                    "Close receipt identifies activated snapshot");
         end;
         declare
            New_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         begin
            Assert (not Propose_Close (New_Paths, Close).Success,
                    "Second close of one item fails closed");
         end;
         declare
            New_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
            View      : constant Attention_View := Execute (New_Paths);
         begin
            Assert (View.Success and then View.Count = 0,
                    "Closed item leaves the open answer");
         end;
      end;

      --  A close proposal from a stale snapshot is rejected.
      declare
         Raise_Second : constant Raise_Intent :=
           (Context => Make_Description ("Deep clean"),
            Due     => (Kind => No_Due_Date));
         Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
         Raise_P : constant Proposal_Result :=
           Propose_Raise (Paths, Raise_Second);
         Raise_R : constant Attention_Receipt := Commit (Raise_P.Proposal);
         Fresh   : constant Path_Config := Resolve_Paths (Test_Dir);
         Stale_C : constant Close_Intent :=
           (Target_Id => Make_Token ("att0002"),
            Kind      => Closure_Dropped,
            Known_On  => Make_Date (2026, 9, 21));
         Stale_P : constant Proposal_Result := Propose_Close (Fresh, Stale_C);
         Bump    : constant Proposal_Result :=
           Propose_Raise (Fresh,
                          (Context => Make_Description ("Mystery noise"),
                           Due     => (Kind => Due_Undetermined)));
         Bump_R  : constant Attention_Receipt := Commit (Bump.Proposal);
         Stale_R : constant Attention_Receipt := Commit (Stale_P.Proposal);
      begin
         Assert (Raise_R.Success, "Second raise commits");
         Assert (Stale_P.Success, "Stale-scenario close proposes cleanly");
         Assert (Bump_R.Success, "Advancing raise commits");
         Assert (not Stale_R.Success,
                 "Close proposal from stale snapshot is rejected");
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;
end Test_Attention_Command;
