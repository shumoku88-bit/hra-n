with Ada.Directories;
with HRA_N.Application.Capacity_Command; use HRA_N.Application.Capacity_Command;
with HRA_N.Application.Capacity_Query; use HRA_N.Application.Capacity_Query;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with Test_Support; use Test_Support;

package body Test_Capacity_Command is

   function Purpose_Coord (Name : String) return Capacity_Coordinate is
     (Make_Purpose_Coordinate (Make_Token (Name)));

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_capacity_command";
      Transfer : constant Transfer_Intent :=
        (From_Coord   => Make_Unallocated_Coordinate,
         To_Coord     => Purpose_Coord ("food"),
         Amount       => 5_000,
         Currency     => Make_Token ("jpy"),
         Effective_On => Make_Date (2026, 9, 1));
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Assert (Initialize_Household (Test_Dir).Success,
              "Capacity fixture initializes");

      --  Fresh households carry no capacity evidence: vacuously complete.
      declare
         View : constant Capacity_View :=
           Execute (Resolve_Paths (Test_Dir));
      begin
         Assert (View.Success, "Empty capacity query succeeds");
         Assert (View.Complete, "Empty capacity evidence is complete");
         Assert (View.Count = 1, "Empty query reports unallocated only");
      end;

      --  Transfer intent commits through the generation transaction.
      declare
         Paths    : constant Path_Config := Resolve_Paths (Test_Dir);
         Proposed : constant Proposal_Result := Propose_Transfer (Paths, Transfer);
      begin
         Assert (Proposed.Success, "Capacity transfer intent produces proposal");
         Assert (Proposed_Movement_Id (Proposed.Proposal) = "cap0001",
                 "Transfer proposal allocates next movement identity");
         Assert (Expected_Snapshot (Proposed.Proposal) = "g00000001",
                 "Transfer proposal binds selected snapshot");
         declare
            Receipt : constant Capacity_Receipt := Commit (Proposed.Proposal);
            Retried : constant Capacity_Receipt := Commit (Proposed.Proposal);
         begin
            Assert (Receipt.Success, "Capacity transfer proposal commits");
            Assert (Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len) = "g00000002",
                    "Transfer receipt identifies activated snapshot");
            Assert (Retried.Success, "Capacity transfer retry is idempotent");
            Assert (Retried.Snapshot_Id (1 .. Retried.Snapshot_Len) = "g00000002",
                    "Retry recovers the same receipt");
         end;
      end;

      --  The admitted snapshot carries the movement, its inline effective
      --  date, and exact entitlements.
      declare
         Paths  : constant Path_Config := Resolve_Paths (Test_Dir);
         Policy : constant Policy_Result :=
           Read_Policy_File (Policy_Path_Str (Paths));
         View   : constant Capacity_View := Execute (Paths);
      begin
         Assert (Policy.Success, "Transfer authority snapshot stays admitted");
         Assert (Policy.Capacities.Movement_Count = 1,
                 "One capacity movement retained");
         Assert (Has_Effective_Date
                   (Policy.Capacities,
                    Policy.Capacities.Movements (1).Id),
                 "Transfer carries inline effective evidence");
         Assert (View.Success and then View.Complete,
                 "Effective evidence is complete after transfer");
         Assert (Entitlement_At
                   (Policy.Capacities, Make_Unallocated_Coordinate,
                    Make_Token ("jpy")) = -5_000,
                 "Unallocated entitlement reflects transfer");
         Assert (Entitlement_At
                   (Policy.Capacities, Purpose_Coord ("food"),
                    Make_Token ("jpy")) = 5_000,
                 "Purpose entitlement reflects transfer");
      end;

      --  Guards fail closed: overdraw, same endpoints, bad amount,
      --  non-jpy currency, and unbalanced or duplicate rebalance shapes.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Overdraw : Transfer_Intent := Transfer;
         Same     : Transfer_Intent := Transfer;
         Zero     : Transfer_Intent := Transfer;
         Foreign  : Transfer_Intent := Transfer;
      begin
         Overdraw.From_Coord := Purpose_Coord ("food");
         Overdraw.To_Coord := Purpose_Coord ("misc");
         Overdraw.Amount := 6_000;
         Assert (not Propose_Transfer (Paths, Overdraw).Success,
                 "Transfer driving a purpose negative fails closed");
         Same.To_Coord := Same.From_Coord;
         Assert (not Propose_Transfer (Paths, Same).Success,
                 "Transfer with identical endpoints fails closed");
         Zero.Amount := 0;
         Assert (not Propose_Transfer (Paths, Zero).Success,
                 "Transfer with zero amount fails closed");
         Foreign.Currency := Make_Token ("usd");
         Assert (not Propose_Transfer (Paths, Foreign).Success,
                 "Transfer outside jpy fails closed");
         declare
            Bad : Rebalance_Intent;
         begin
            Bad.Count := 2;
            Bad.Currency := Make_Token ("jpy");
            Bad.Effective_On := Make_Date (2026, 9, 2);
            Bad.Changes (1) :=
              (Coord => Purpose_Coord ("food"), Amount => -1_000);
            Bad.Changes (2) :=
              (Coord => Purpose_Coord ("misc"), Amount => 900);
            Assert (not Propose_Rebalance (Paths, Bad).Success,
                    "Unbalanced rebalance fails closed");
            Bad.Changes (2) :=
              (Coord => Purpose_Coord ("food"), Amount => 1_000);
            Assert (not Propose_Rebalance (Paths, Bad).Success,
                    "Rebalance repeating a coordinate fails closed");
         end;
      end;

      --  A funded rebalance commits; stale proposals are rejected.
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Good  : Rebalance_Intent;
      begin
         Good.Count := 3;
         Good.Currency := Make_Token ("jpy");
         Good.Effective_On := Make_Date (2026, 9, 3);
         Good.Changes (1) :=
           (Coord => Purpose_Coord ("food"), Amount => -1_000);
         Good.Changes (2) :=
           (Coord => Purpose_Coord ("misc"), Amount => 600);
         Good.Changes (3) :=
           (Coord => Make_Unallocated_Coordinate, Amount => 400);
         declare
            Prop : constant Proposal_Result := Propose_Rebalance (Paths, Good);
         begin
            Assert (Prop.Success, "Funded rebalance proposes cleanly");
            Assert (Proposed_Movement_Id (Prop.Proposal) = "cap0002",
                    "Rebalance allocates next movement identity");
            declare
               First_Receipt : constant Capacity_Receipt := Commit (Prop.Proposal);
            begin
               Assert (First_Receipt.Success, "Rebalance commits");
               Assert (First_Receipt.Snapshot_Id
                         (1 .. First_Receipt.Snapshot_Len) = "g00000003",
                       "Rebalance receipt identifies activated snapshot");
            end;
         end;
         declare
            Fresh    : constant Path_Config := Resolve_Paths (Test_Dir);
            Stale_P : constant Proposal_Result := Propose_Rebalance (Fresh, Good);
            Advance : constant Proposal_Result :=
              Propose_Transfer (Fresh, Transfer);
            Advance_R : constant Capacity_Receipt := Commit (Advance.Proposal);
            Stale_R   : constant Capacity_Receipt := Commit (Stale_P.Proposal);
         begin
            Assert (Stale_P.Success, "Stale-scenario rebalance proposes cleanly");
            Assert (Advance_R.Success, "Advancing transfer commits");
            Assert (not Stale_R.Success,
                    "Capacity proposal from stale snapshot is rejected");
         end;
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;
end Test_Capacity_Command;
