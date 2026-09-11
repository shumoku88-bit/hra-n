with Ada.Directories;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Assertion; use HRA_N.Core.Assertion;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Assertion_Command; use HRA_N.Application.Assertion_Command;
with HRA_N.Application.Reconciliation_Query; use HRA_N.Application.Reconciliation_Query;
with HRA_N.Application.Balance_Query; use HRA_N.Application.Balance_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with Test_Support; use Test_Support;

package body Test_Assertion is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_assertion";
   begin
      --  Part 1: Core Assertion Memory
      declare
         Mem     : Assertion_Memory;
         Success : Boolean := False;
         Found   : Boolean := False;
         Item    : Balance_Assertion;
      begin
         Add_Assertion
           (Mem,
            (Id          => (Token => Make_Token ("a0001")),
             Valid_On    => Make_Date (2026, 9, 1),
             Coordinate  => (Locus   => (Token => Make_Token ("cash")),
                             Measure => (Token => Make_Token ("jpy"))),
             Amount      => 10_000,
             Description => Make_Token ("Opening count")),
            Success);
         Assert (Success, "First assertion added");

         --  Duplicate ID rejected
         Add_Assertion
           (Mem,
            (Id          => (Token => Make_Token ("a0001")),
             Valid_On    => Make_Date (2026, 9, 2),
             Coordinate  => (Locus   => (Token => Make_Token ("bank")),
                             Measure => (Token => Make_Token ("jpy"))),
             Amount      => 20_000,
             Description => Make_Token ("Duplicate ID")),
            Success);
         Assert (not Success, "Duplicate assertion ID rejected");

         --  Add second assertion for same coordinate later
         Add_Assertion
           (Mem,
            (Id          => (Token => Make_Token ("a0002")),
             Valid_On    => Make_Date (2026, 9, 15),
             Coordinate  => (Locus   => (Token => Make_Token ("cash")),
                             Measure => (Token => Make_Token ("jpy"))),
             Amount      => 8_000,
             Description => Make_Token ("Mid-month count")),
            Success);
         Assert (Success, "Second assertion added");

         --  Find by ID
         Find_Assertion (Mem, (Token => Make_Token ("a0001")), Item, Found);
         Assert (Found and then Item.Amount = 10_000, "Found a0001 by ID");

         --  Find latest as of 2026-09-10 (should be a0001)
         Find_Latest_Assertion
           (Mem,
            (Locus   => (Token => Make_Token ("cash")),
             Measure => (Token => Make_Token ("jpy"))),
            Make_Date (2026, 9, 10),
            Item,
            Found);
         Assert (Found and then Item.Amount = 10_000, "Latest as of 09-10 is a0001 (10000)");

         --  Find latest as of 2026-09-20 (should be a0002)
         Find_Latest_Assertion
           (Mem,
            (Locus   => (Token => Make_Token ("cash")),
             Measure => (Token => Make_Token ("jpy"))),
            Make_Date (2026, 9, 20),
            Item,
            Found);
         Assert (Found and then Item.Amount = 8_000, "Latest as of 09-20 is a0002 (8000)");
      end;

      --  Part 2: Assertion Lifecycle in Household Authority
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Assert (Initialize_Household (Test_Dir).Success, "Fixture initializes");

      --  Record an initial transaction: bank -> cash 10000 on 2026-09-01
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Prop  : constant HRA_N.Application.Movement_Command.Proposal_Result :=
           HRA_N.Application.Movement_Command.Propose
             (Paths,
              (From_Locus  => (Token => Make_Token ("bank")),
               To_Locus    => (Token => Make_Token ("cash")),
               Measure     => (Token => Make_Token ("jpy")),
               Amount      => 10_000,
               Valid_On    => Make_Date (2026, 9, 1),
               Description => Make_Token ("ATM withdrawal")));
      begin
         Assert (Commit (Prop.Proposal).Success, "ATM withdrawal commits (cash is +10000)");
      end;

      --  Propose and commit matching assertion: cash is 10000 on 2026-09-01
      declare
         Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
         Prop    : constant HRA_N.Application.Assertion_Command.Proposal_Result :=
           HRA_N.Application.Assertion_Command.Propose
             (Paths,
              (Id          => (Length => 0, Value => [others => ' ']),
               Valid_On    => Make_Date (2026, 9, 1),
               Locus       => (Token => Make_Token ("cash")),
               Measure     => (Token => Make_Token ("jpy")),
               Amount      => 10_000,
               Description => Make_Token ("Cash drawer count")));
      begin
         Assert (Prop.Success, "Assertion proposal succeeds");
         declare
            Receipt : constant Assertion_Receipt := Commit (Prop.Proposal);
         begin
            Assert (Receipt.Success, "Assertion commits to snapshot g00000003");
            Assert (Receipt.Assertion_Id (1 .. Receipt.Assertion_Id_Len) = "a0001",
                    "Allocated assertion ID is a0001");
         end;
      end;

      --  Verify Reconciliation Query on matching assertion
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Reconciliation_View :=
           HRA_N.Application.Reconciliation_Query.Execute (Paths);
      begin
         Assert (View.Status = Query_Complete, "Reconciliation query is complete");
         Assert (View.Total_Count = 1, "Total assertions is 1");
         Assert (View.Matched_Count = 1, "Matched count is 1");
         Assert (View.Mismatched_Count = 0, "Mismatched count is 0");
         Assert (View.Rows (1).Is_Matched, "Row 1 is MATCH");
         Assert (View.Rows (1).Diff = 0, "Row 1 diff is 0");
      end;

      --  Verify Balance Query: cash is Status_Known_Zero with 0 conflict
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Balance_View :=
           HRA_N.Application.Balance_Query.Execute (Paths);
      begin
         Assert (View.Status = Query_Complete, "Balance query is complete");
         Assert (View.Total_Conflict_Count = 0, "Total conflict count is 0");

         for I in 1 .. View.Row_Count loop
            if View.Rows (I).Locus.Value (1 .. View.Rows (I).Locus.Length) = "cash" then
               Assert (View.Rows (I).Epistemic_Status = Status_Known_Zero,
                       "cash status is Status_Known_Zero");
               Assert (View.Rows (I).Amount = 10_000, "cash amount is 10000");
            end if;
         end loop;
      end;

      --  Now propose a conflicting assertion: bank is asserted as 50000, but is -10000!
      declare
         Paths   : constant Path_Config := Resolve_Paths (Test_Dir);
         Prop    : constant HRA_N.Application.Assertion_Command.Proposal_Result :=
           HRA_N.Application.Assertion_Command.Propose
             (Paths,
              (Id          => (Length => 0, Value => [others => ' ']),
               Valid_On    => Make_Date (2026, 9, 2),
               Locus       => (Token => Make_Token ("bank")),
               Measure     => (Token => Make_Token ("jpy")),
               Amount      => 50_000,
               Description => Make_Token ("Conflicting bank claim")));
      begin
         Assert (Prop.Success, "Conflicting assertion proposal succeeds");
         declare
            Receipt : constant Assertion_Receipt := Commit (Prop.Proposal);
         begin
            Assert (Receipt.Success, "Conflicting assertion commits to snapshot g00000004");
            Assert (Receipt.Assertion_Id (1 .. Receipt.Assertion_Id_Len) = "a0002",
                    "Allocated assertion ID is a0002");
         end;
      end;

      --  Verify Reconciliation Query detects MISMATCH
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Reconciliation_View :=
           HRA_N.Application.Reconciliation_Query.Execute (Paths);
      begin
         Assert (View.Total_Count = 2, "Total assertions is 2");
         Assert (View.Matched_Count = 1, "Matched count is 1");
         Assert (View.Mismatched_Count = 1, "Mismatched count is 1 (bank mismatch)");

         --  Row 2 is bank: asserted 50000, computed -10000, diff +60000
         Assert (not View.Rows (2).Is_Matched, "Row 2 is MISMATCH");
         Assert (View.Rows (2).Computed_Amount = -10_000, "bank computed is -10000");
         Assert (View.Rows (2).Asserted_Amount = 50_000, "bank asserted is 50000");
         Assert (View.Rows (2).Diff = 60_000, "bank diff is +60000");
      end;

      --  Verify Balance Query detects Status_Conflict on bank!
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Balance_View :=
           HRA_N.Application.Balance_Query.Execute (Paths);
      begin
         Assert (View.Total_Conflict_Count = 1, "Total conflict count is 1");

         for I in 1 .. View.Row_Count loop
            if View.Rows (I).Locus.Value (1 .. View.Rows (I).Locus.Length) = "bank" then
               Assert (View.Rows (I).Epistemic_Status = Status_Conflict,
                       "bank status is Status_Conflict");
            end if;
         end loop;
      end;

      --  Clean up fixture
      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;

end Test_Assertion;
