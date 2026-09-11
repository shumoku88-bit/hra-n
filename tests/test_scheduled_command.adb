with Ada.Directories;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Scheduled_Command; use HRA_N.Application.Scheduled_Command;
with HRA_N.Application.Scheduled_Query; use HRA_N.Application.Scheduled_Query;
with HRA_N.Application.Scheduled_Detail_Query; use HRA_N.Application.Scheduled_Detail_Query;
with HRA_N.Application.Actual_Detail_Query; use HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with Test_Support; use Test_Support;

package body Test_Scheduled_Command is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_scheduled_command";
      Create_1 : constant Create_Intent :=
        (Id           => (Length => 0, Value => [others => ' ']),
         Expected_Day => Make_Date (2026, 9, 15),
         From_Locus   => (Token => Make_Token ("cash")),
         To_Locus     => (Token => Make_Token ("food")),
         Measure      => (Token => Make_Token ("jpy")),
         Amount       => 1_200);
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Assert (Initialize_Household (Test_Dir).Success,
              "Scheduled command fixture initializes");

      --  1. Validation failures before proposal
      declare
         Invalid : Create_Intent := Create_1;
      begin
         Invalid.Amount := 0;
         Assert (not Propose_Create (Resolve_Paths (Test_Dir), Invalid).Success,
                 "Zero amount fails before proposal creation");

         Invalid := Create_1;
         Invalid.To_Locus := Invalid.From_Locus;
         Assert (not Propose_Create (Resolve_Paths (Test_Dir), Invalid).Success,
                 "Identical loci fail before proposal creation");

         Invalid := Create_1;
         Invalid.From_Locus := (Token => Make_Token ("bad:locus"));
         Assert (not Propose_Create (Resolve_Paths (Test_Dir), Invalid).Success,
                 "Unencodable locus fails before proposal creation");
      end;

      --  2. Valid creation and idempotent commit
      declare
         Paths    : constant Path_Config := Resolve_Paths (Test_Dir);
         Proposed : constant Proposal_Result := Propose_Create (Paths, Create_1);
      begin
         Assert (Proposed.Success, "Typed create intent produces proposal");
         Assert (Expected_Snapshot (Proposed.Proposal) = "g00000001",
                 "Proposal binds selected snapshot");
         Assert (Proposed_Scheduled_Id (Proposed.Proposal) = "s0001",
                 "Proposal allocates deterministic scheduled id");

         declare
            Receipt : constant Scheduled_Receipt := Commit (Proposed.Proposal);
            Retried : constant Scheduled_Receipt := Commit (Proposed.Proposal);
         begin
            Assert (Receipt.Success, "Create proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000002",
                    "Receipt identifies activated snapshot");
            Assert (Receipt.Scheduled_Id (1 .. Receipt.Scheduled_Id_Len) = "s0001",
                    "Receipt identifies allocated scheduled id");
            Assert (Retried.Success, "Create proposal retry is idempotent");
            Assert (Retried.Snapshot_Id (1 .. Retried.Snapshot_Len) = "g00000002",
                    "Retry recovers the same receipt");
            Assert (not Ada.Directories.Exists
                      (Test_Dir & "/.hra/generations/g00000003"),
                    "Retry does not create another generation");
         end;

         --  Verify with Scheduled_Query
         declare
            New_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
            View      : constant Scheduled_View :=
              HRA_N.Application.Scheduled_Query.Execute
                (New_Paths, (Scope => Scope_Current_Open,
                             Selected_Day => Make_Date (2026, 9, 15),
                             Ordering => Order_Due_Ascending));
         begin
            Assert (View.Open_Count = 1, "Scheduled query sees 1 open item");
            Assert (View.Rows (1).Id.Value (1 .. View.Rows (1).Id.Length) = "s0001",
                    "Open item is s0001");
            Assert (View.Rows (1).Status = Status_Open, "s0001 is Open");
         end;
      end;

      --  3. Complete s0001 (creating Actual transaction in Journal)
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Complete_1 : constant Complete_Intent :=
           (Target_Id          => Make_Token ("s0001"),
            Has_Execution_Date => True,
            Execution_Date     => Make_Date (2026, 9, 16),
            Description        => Make_Token ("Lunch with colleagues"),
            Existing_Actual_Id => (Length => 0, Value => [others => ' ']));
         Proposed : constant Proposal_Result :=
           Propose_Completion (Paths, Complete_1);
      begin
         Assert (Proposed.Success, "Completion intent produces proposal");
         Assert (Expected_Snapshot (Proposed.Proposal) = "g00000002",
                 "Completion proposal binds snapshot g00000002");
         Assert (Proposed_Secondary_Id (Proposed.Proposal) = "e0001",
                 "Completion allocates next event id e0001");

         declare
            Receipt : constant Scheduled_Receipt := Commit (Proposed.Proposal);
         begin
            Assert (Receipt.Success, "Completion proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000003",
                    "Receipt identifies generation g00000003");
            Assert (Receipt.Scheduled_Id (1 .. Receipt.Scheduled_Id_Len) = "s0001",
                    "Receipt identifies s0001");
            Assert (Receipt.Secondary_Id (1 .. Receipt.Secondary_Id_Len) = "e0001",
                    "Receipt identifies created actual e0001");
         end;

         --  Verify scheduled detail and actual detail
         declare
            New_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
            Sched_Det : constant Scheduled_Detail_View :=
              HRA_N.Application.Scheduled_Detail_Query.Execute
                (New_Paths, Make_Token ("s0001"));
            Act_Det   : constant Actual_Detail_View :=
              HRA_N.Application.Actual_Detail_Query.Execute
                (New_Paths, Make_Token ("e0001"));
         begin
            Assert (Sched_Det.Lifecycle_Status = Status_Completed,
                    "s0001 detail is Completed");
            Assert (Sched_Det.Terminal_Ref.Value (1 .. Sched_Det.Terminal_Ref.Length) = "e0001",
                    "s0001 terminal reference is e0001");
            Assert (Act_Det.Status = Query_Complete, "e0001 actual detail exists");
            Assert (Act_Det.Valid_On.Day = 16, "e0001 date is 2026-09-16");
            Assert (Act_Det.Effect_Count = 2, "e0001 has 2 effects");
         end;

         --  Double completion on already completed s0001 must fail
         declare
            New_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         begin
            Assert (not Propose_Completion (New_Paths, Complete_1).Success,
                    "Proposing completion on already completed target fails closed");
         end;
      end;

      --  4. Create s0002 and Retire it
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Create_2 : constant Create_Intent :=
           (Id           => (Length => 0, Value => [others => ' ']),
            Expected_Day => Make_Date (2026, 9, 25),
            From_Locus   => (Token => Make_Token ("smbc")),
            To_Locus     => (Token => Make_Token ("rent")),
            Measure      => (Token => Make_Token ("jpy")),
            Amount       => 50_000);
         Prop_Create : constant Proposal_Result := Propose_Create (Paths, Create_2);
      begin
         Assert (Prop_Create.Success, "Create s0002 succeeds");
         declare
            Rec : constant Scheduled_Receipt := Commit (Prop_Create.Proposal);
         begin
            Assert (Rec.Success and then Rec.Scheduled_Id (1 .. Rec.Scheduled_Id_Len) = "s0002",
                    "s0002 created in snapshot g00000004");
         end;

         declare
            New_Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
            Ret_Intent  : constant Retire_Intent := (Target_Id => Make_Token ("s0002"));
            Prop_Retire : constant Proposal_Result := Propose_Retirement (New_Paths, Ret_Intent);
         begin
            Assert (Prop_Retire.Success, "Retirement intent produces proposal");
            declare
               Rec : constant Scheduled_Receipt := Commit (Prop_Retire.Proposal);
            begin
               Assert (Rec.Success, "Retirement proposal commits");
               Assert (Rec.Snapshot_Id (1 .. Rec.Snapshot_Len) = "g00000005",
                       "Retirement activates g00000005");
            end;

            declare
               After_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
               Sched_Det   : constant Scheduled_Detail_View :=
                 HRA_N.Application.Scheduled_Detail_Query.Execute
                   (After_Paths, Make_Token ("s0002"));
            begin
               Assert (Sched_Det.Lifecycle_Status = Status_Retired, "s0002 is Retired");
               Assert (not Propose_Retirement (After_Paths, Ret_Intent).Success,
                       "Retiring already retired target fails closed");
            end;
         end;
      end;

      --  5. Create s0003 and Replace it with s0004
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Create_3 : constant Create_Intent :=
           (Id           => (Length => 0, Value => [others => ' ']),
            Expected_Day => Make_Date (2026, 9, 20),
            From_Locus   => (Token => Make_Token ("cash")),
            To_Locus     => (Token => Make_Token ("books")),
            Measure      => (Token => Make_Token ("jpy")),
            Amount       => 2_000);
         Prop_Create : constant Proposal_Result := Propose_Create (Paths, Create_3);
      begin
         Assert (Prop_Create.Success, "Create s0003 succeeds");
         declare
            Rec : constant Scheduled_Receipt := Commit (Prop_Create.Proposal);
         begin
            Assert (Rec.Success and then Rec.Scheduled_Id (1 .. Rec.Scheduled_Id_Len) = "s0003",
                    "s0003 created in snapshot g00000006");
         end;

         declare
            New_Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
            Repl_Intent : constant Replace_Intent :=
              (Target_Id    => Make_Token ("s0003"),
               New_Id       => (Length => 0, Value => [others => ' ']),
               Expected_Day => Make_Date (2026, 9, 22),
               From_Locus   => (Token => Make_Token ("cash")),
               To_Locus     => (Token => Make_Token ("books")),
               Measure      => (Token => Make_Token ("jpy")),
               Amount       => 2_500);
            Prop_Repl   : constant Proposal_Result :=
              Propose_Replacement (New_Paths, Repl_Intent);
         begin
            Assert (Prop_Repl.Success, "Replacement intent produces proposal");
            Assert (Proposed_Secondary_Id (Prop_Repl.Proposal) = "s0004",
                    "Replacement allocates new id s0004");
            declare
               Rec : constant Scheduled_Receipt := Commit (Prop_Repl.Proposal);
            begin
               Assert (Rec.Success, "Replacement commits");
               Assert (Rec.Snapshot_Id (1 .. Rec.Snapshot_Len) = "g00000007",
                       "Replacement activates g00000007");
               Assert (Rec.Scheduled_Id (1 .. Rec.Scheduled_Id_Len) = "s0003",
                       "Receipt original id is s0003");
               Assert (Rec.Secondary_Id (1 .. Rec.Secondary_Id_Len) = "s0004",
                       "Receipt new id is s0004");
            end;

            declare
               After_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
               Det_Orig    : constant Scheduled_Detail_View :=
                 HRA_N.Application.Scheduled_Detail_Query.Execute
                   (After_Paths, Make_Token ("s0003"));
               Det_New     : constant Scheduled_Detail_View :=
                 HRA_N.Application.Scheduled_Detail_Query.Execute
                   (After_Paths, Make_Token ("s0004"));
            begin
               Assert (Det_Orig.Lifecycle_Status = Status_Replaced, "s0003 is Replaced");
               Assert (Det_Orig.Terminal_Ref.Value (1 .. Det_Orig.Terminal_Ref.Length) = "s0004",
                       "s0003 replacement link is s0004");
               Assert (Det_New.Lifecycle_Status = Status_Open, "s0004 is Open");
               Assert (Det_New.Changes (2).Amount = 2_500, "s0004 amount is 2500");
               Assert (not Propose_Replacement (After_Paths, Repl_Intent).Success,
                       "Replacing already replaced target fails closed");
            end;
         end;
      end;

      --  6. Create s0005 and Complete by referencing existing Actual e0001
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Create_5 : constant Create_Intent :=
           (Id           => (Length => 0, Value => [others => ' ']),
            Expected_Day => Make_Date (2026, 9, 30),
            From_Locus   => (Token => Make_Token ("cash")),
            To_Locus     => (Token => Make_Token ("food")),
            Measure      => (Token => Make_Token ("jpy")),
            Amount       => 1_200);
         Prop_Create : constant Proposal_Result := Propose_Create (Paths, Create_5);
      begin
         Assert (Prop_Create.Success, "Create s0005 succeeds");
         declare
            Rec : constant Scheduled_Receipt := Commit (Prop_Create.Proposal);
         begin
            Assert (Rec.Success and then Rec.Scheduled_Id (1 .. Rec.Scheduled_Id_Len) = "s0005",
                    "s0005 created in snapshot g00000008");
         end;

         declare
            New_Paths       : constant Path_Config := Resolve_Paths (Test_Dir);
            Missing_Actual  : constant Complete_Intent :=
              (Target_Id          => Make_Token ("s0005"),
               Has_Execution_Date => False,
               Execution_Date     => Make_Date (2026, 9, 30),
               Description        => (Length => 0, Value => [others => ' ']),
               Existing_Actual_Id => Make_Token ("e9999"));
            Existing_Actual : constant Complete_Intent :=
              (Target_Id          => Make_Token ("s0005"),
               Has_Execution_Date => False,
               Execution_Date     => Make_Date (2026, 9, 30),
               Description        => (Length => 0, Value => [others => ' ']),
               Existing_Actual_Id => Make_Token ("e0001"));
         begin
            Assert (not Propose_Completion (New_Paths, Missing_Actual).Success,
                    "Referencing non-existent actual event fails closed");

            declare
               Prop_Comp : constant Proposal_Result :=
                 Propose_Completion (New_Paths, Existing_Actual);
            begin
               Assert (Prop_Comp.Success, "Referencing existing actual succeeds");
               declare
                  Rec : constant Scheduled_Receipt := Commit (Prop_Comp.Proposal);
               begin
                  Assert (Rec.Success, "Completion referencing existing actual commits");
                  Assert (Rec.Snapshot_Id (1 .. Rec.Snapshot_Len) = "g00000009",
                          "Activates snapshot g00000009");
               end;

               declare
                  After_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
                  Det         : constant Scheduled_Detail_View :=
                    HRA_N.Application.Scheduled_Detail_Query.Execute
                      (After_Paths, Make_Token ("s0005"));
               begin
                  Assert (Det.Lifecycle_Status = Status_Completed, "s0005 is Completed");
                  Assert (Det.Terminal_Ref.Value (1 .. Det.Terminal_Ref.Length) = "e0001",
                          "s0005 links to e0001");
               end;
            end;
         end;
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;

end Test_Scheduled_Command;
