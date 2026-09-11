with Ada.Directories;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
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
         Invalid := Intent;
         Invalid.To_Locus := (Token => Make_Token ("observed-only"));
         Assert (not Propose (Resolve_Paths (Test_Dir), Invalid).Success,
                 "Unadmitted movement Locus fails closed");
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

      declare
         Paths       : constant Path_Config := Resolve_Paths (Test_Dir);
         Corr_Intent : constant Correction_Intent :=
           (Target_Id   => Make_Token ("e0001"),
            From_Locus  => (Token => Make_Token ("cash")),
            To_Locus    => (Token => Make_Token ("food")),
            Measure     => (Token => Make_Token ("jpy")),
            Amount      => 1_500,
            Valid_On    => Make_Date (2026, 9, 15),
            Description => Make_Token ("Corrected Lunch"));
         Corr_Prop   : constant Proposal_Result :=
           Propose_Correction (Paths, Corr_Intent);
      begin
         Assert (Corr_Prop.Success, "Correction intent produces proposal");
         Assert (Replaced_Target_Id (Corr_Prop.Proposal) = "e0001",
                 "Proposal records target to replace");
         Assert (Proposed_Event_Id (Corr_Prop.Proposal) = "e0003",
                 "Proposal allocates next event id");
         declare
            Corr_Receipt : constant Movement_Receipt := Commit (Corr_Prop.Proposal);
         begin
            Assert (Corr_Receipt.Success, "Correction proposal commits");
            Assert (Corr_Receipt.Snapshot_Id (1 .. Corr_Receipt.Snapshot_Len) = "g00000004",
                    "Receipt identifies new generation");
         end;

         declare
            New_Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
            Branch_Prop : constant Proposal_Result :=
              Propose_Correction (New_Paths, Corr_Intent);
            Missing_Intent : Correction_Intent := Corr_Intent;
         begin
            Assert (not Branch_Prop.Success,
                    "Proposing correction on already superseded target fails closed");
            Missing_Intent.Target_Id := Make_Token ("absent");
            Assert (not Propose_Correction (New_Paths, Missing_Intent).Success,
                    "Proposing correction on absent target fails closed");
         end;
      end;

      --  Reversal through the generation authority. e0002 is active with
      --  cash -1250 / food +1250; the reversal must carry the exact inverse
      --  effects and retain its link without superseding the target.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Rev_Intent : constant Reversal_Intent :=
           (Target_Id   => Make_Token ("e0002"),
            Valid_On    => Make_Date (2026, 9, 16),
            Description => Make_Token ("Voided lunch"));
         Rev_Prop : constant Proposal_Result := Propose_Reversal (Paths, Rev_Intent);
      begin
         Assert (Rev_Prop.Success, "Reversal intent produces proposal");
         Assert (Replaced_Target_Id (Rev_Prop.Proposal) = "e0002",
                 "Reversal proposal records its target");
         Assert (Proposed_Event_Id (Rev_Prop.Proposal) = "e0004",
                 "Reversal proposal allocates next event id");
         Assert (Expected_Snapshot (Rev_Prop.Proposal) = "g00000004",
                 "Reversal proposal binds selected snapshot");
         declare
            Receipt : constant Movement_Receipt := Commit (Rev_Prop.Proposal);
            Retried : constant Movement_Receipt := Commit (Rev_Prop.Proposal);
         begin
            Assert (Receipt.Success, "Reversal proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000005",
                    "Reversal receipt identifies activated snapshot");
            Assert (Retried.Success, "Reversal proposal retry is idempotent");
            Assert (Retried.Snapshot_Id (1 .. Retried.Snapshot_Len) = "g00000005",
                    "Retry recovers the same receipt");
         end;
      end;

      --  The admitted journal retains the reversal link and the exact inverse
      --  effects while the target stays effective (not superseded).
      declare
         Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
         Journal : constant Journal_Result :=
           Read_Journal_File (Journal_Path_Str (Paths));
         Target_Ev   : Event;
         Reversal_Ev : Event;
         Found_Target   : Boolean := False;
         Found_Reversal : Boolean := False;
      begin
         Assert (Journal.Success, "Reversed authority snapshot stays admitted");
         for Item of Journal.Events loop
            if Equal_Token (Id (Item).Token, Make_Token ("e0002")) then
               Target_Ev := Item;
               Found_Target := True;
            elsif Equal_Token (Id (Item).Token, Make_Token ("e0004")) then
               Reversal_Ev := Item;
               Found_Reversal := True;
            end if;
         end loop;
         Assert (Found_Target and then Found_Reversal,
                 "Target and reversal events are both retained");
         Assert (Effect_Count (Target_Ev) = Effect_Count (Reversal_Ev),
                 "Reversal preserves effect arity");
         for I in 1 .. Effect_Count (Target_Ev) loop
            declare
               T : constant Effect := Effect_At (Target_Ev, I);
               R : constant Effect := Effect_At (Reversal_Ev, I);
            begin
               Assert (Equal_Token (T.Locus.Token, R.Locus.Token)
                       and then Equal_Token (T.Measure.Token, R.Measure.Token)
                       and then R.Amount.Quanta = -T.Amount.Quanta,
                       "Reversal effect is the exact inverse at the same coordinate");
            end;
         end loop;
         declare
            Meta  : Transaction_Metadata_Entry;
            Found : Boolean;
         begin
            Find_Metadata
              (Journal.Metadata, Id (Reversal_Ev), Meta, Found);
            Assert (Found and then Meta.Reverses.Present
                    and then Equal_Token
                      (Meta.Reverses.Value.Token, Make_Token ("e0002")),
                    "Reversal link is retained in transaction metadata");
         end;
         declare
            Successor  : Event_Id;
            Succ_Found : Boolean;
            Reverser   : Event_Id;
            Rev_Found  : Boolean;
         begin
            Find_Successor
              (Journal.Metadata, Id (Target_Ev), Successor, Succ_Found);
            Assert (not Succ_Found,
                    "Reversed target is not superseded");
            Find_Reverser
              (Journal.Metadata, Id (Target_Ev), Reverser, Rev_Found);
            Assert (Rev_Found
                    and then Equal_Token (Reverser.Token, Id (Reversal_Ev).Token),
                    "Reverser lookup resolves the reversal event");
         end;
      end;

      --  Reversal laws fail closed: double reversal, superseded or absent
      --  targets, chains, and correction of a reversed target.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Rev_Intent : constant Reversal_Intent :=
           (Target_Id   => Make_Token ("e0002"),
            Valid_On    => Make_Date (2026, 9, 16),
            Description => Make_Token ("Second void"));
         Superseded_Intent : Reversal_Intent := Rev_Intent;
         Absent_Intent     : Reversal_Intent := Rev_Intent;
         Chain_Intent      : Reversal_Intent := Rev_Intent;
      begin
         Assert (not Propose_Reversal (Paths, Rev_Intent).Success,
                 "Proposing a second reversal of one target fails closed");
         Superseded_Intent.Target_Id := Make_Token ("e0001");
         Assert (not Propose_Reversal (Paths, Superseded_Intent).Success,
                 "Proposing reversal of a superseded target fails closed");
         Absent_Intent.Target_Id := Make_Token ("absent");
         Assert (not Propose_Reversal (Paths, Absent_Intent).Success,
                 "Proposing reversal of an absent target fails closed");
         Chain_Intent.Target_Id := Make_Token ("e0004");
         Assert (not Propose_Reversal (Paths, Chain_Intent).Success,
                 "Proposing reversal of a reversal fails closed");
         declare
            Corr_Of_Reversed : constant Correction_Intent :=
              (Target_Id   => Make_Token ("e0002"),
               From_Locus  => (Token => Make_Token ("cash")),
               To_Locus    => (Token => Make_Token ("food")),
               Measure     => (Token => Make_Token ("jpy")),
               Amount      => 1_250,
               Valid_On    => Make_Date (2026, 9, 17),
               Description => Make_Token ("Edit reversed lunch"));
         begin
            Assert (not Propose_Correction (Paths, Corr_Of_Reversed).Success,
                    "Proposing correction of a reversed target fails closed");
         end;
      end;

      --  A reversal proposal from a stale snapshot is rejected after the
      --  authority advances.
      declare
         Paths    : constant Path_Config := Resolve_Paths (Test_Dir);
         Stale_I  : constant Reversal_Intent :=
           (Target_Id   => Make_Token ("e0003"),
            Valid_On    => Make_Date (2026, 9, 16),
            Description => Make_Token ("Stale void"));
         Stale_P  : constant Proposal_Result := Propose_Reversal (Paths, Stale_I);
         Advance_I : Movement_Intent := Intent;
      begin
         Assert (Stale_P.Success, "Stale-scenario reversal proposes cleanly");
         Advance_I.Amount := 100;
         declare
            Advance_P : constant Proposal_Result := Propose (Paths, Advance_I);
            Advance_R : constant Movement_Receipt := Commit (Advance_P.Proposal);
            Stale_R   : constant Movement_Receipt := Commit (Stale_P.Proposal);
         begin
            Assert (Advance_R.Success, "Advancing movement commits");
            Assert (not Stale_R.Success,
                    "Reversal proposal from stale snapshot is rejected");
         end;
      end;

      --  Split movements carry signed changes at explicit coordinates
      --  with a measure column defaulting to jpy at the entrances.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Split : Record_Split_Intent;
      begin
         Split.Count := 3;
         Split.Valid_On := Make_Date (2026, 9, 17);
         Split.Description := Make_Token ("Party");
         Split.Changes (1) :=
           (Locus   => (Token => Make_Token ("cash")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => -1_500);
         Split.Changes (2) :=
           (Locus   => (Token => Make_Token ("food")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => 1_000);
         Split.Changes (3) :=
           (Locus   => (Token => Make_Token ("misc")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => 500);
         declare
            Prop : constant Proposal_Result := Propose_Split (Paths, Split);
         begin
            Assert (Prop.Success, "Split intent produces proposal");
            Assert (Proposed_Event_Id (Prop.Proposal) = "e0006",
                    "Split proposal allocates next event id");
            declare
               Receipt : constant Movement_Receipt := Commit (Prop.Proposal);
               Retried : constant Movement_Receipt := Commit (Prop.Proposal);
            begin
               Assert (Receipt.Success, "Split proposal commits");
               Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000007",
                       "Split receipt identifies activated snapshot");
               Assert (Retried.Success, "Split proposal retry is idempotent");
            end;
         end;
         declare
            Journal : constant Journal_Result :=
              Read_Journal_File (Journal_Path_Str (Resolve_Paths (Test_Dir)));
            Found_E5 : Boolean := False;
         begin
            Assert (Journal.Success, "Split authority snapshot stays admitted");
            for Item of Journal.Events loop
               if Equal_Token (Id (Item).Token, Make_Token ("e0006")) then
                  Found_E5 := True;
                  Assert (Effect_Count (Item) = 3,
                          "Split retains all three effects");
               end if;
            end loop;
            Assert (Found_E5, "Split event is retained");
         end;
      end;

      --  Split guards fail closed, including the explicit jpy-only gate
      --  that multi-currency support will open.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Base  : Record_Split_Intent;
      begin
         Base.Count := 3;
         Base.Valid_On := Make_Date (2026, 9, 17);
         Base.Description := Make_Token ("Party");
         Base.Changes (1) :=
           (Locus   => (Token => Make_Token ("cash")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => -1_500);
         Base.Changes (2) :=
           (Locus   => (Token => Make_Token ("food")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => 1_000);
         Base.Changes (3) :=
           (Locus   => (Token => Make_Token ("misc")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => 500);
         declare
            Unbalanced : Record_Split_Intent := Base;
            Duplicate  : Record_Split_Intent := Base;
            Foreign    : Record_Split_Intent := Base;
            Unknown    : Record_Split_Intent := Base;
            Single     : Record_Split_Intent := Base;
         begin
            Unbalanced.Changes (3) :=
              (Locus   => (Token => Make_Token ("misc")),
               Measure => (Token => Make_Token ("jpy")),
               Amount  => 600);
            Assert (not Propose_Split (Paths, Unbalanced).Success,
                    "Unbalanced split fails closed");
            Duplicate.Changes (3) :=
              (Locus   => (Token => Make_Token ("food")),
               Measure => (Token => Make_Token ("jpy")),
               Amount  => 500);
            Assert (not Propose_Split (Paths, Duplicate).Success,
                    "Split repeating a coordinate fails closed");
            Foreign.Changes (3) :=
              (Locus   => (Token => Make_Token ("misc")),
               Measure => (Token => Make_Token ("usd")),
               Amount  => 500);
            Assert (not Propose_Split (Paths, Foreign).Success,
                    "Non-jpy split fails closed with an explicit gate");
            Unknown.Changes (3) :=
              (Locus   => (Token => Make_Token ("observed-only")),
               Measure => (Token => Make_Token ("jpy")),
               Amount  => 500);
            Assert (not Propose_Split (Paths, Unknown).Success,
                    "Split with an unadmitted Locus fails closed");
            Single.Count := 1;
            Assert (not Propose_Split (Paths, Single).Success,
                    "Single-change split fails closed");
         end;
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;
end Test_Movement_Command;
