with Ada.Directories;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Balance_Query; use HRA_N.Application.Balance_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with Test_Support; use Test_Support;

package body Test_Balance_Query is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_balance_query";
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Assert (Initialize_Household (Test_Dir).Success,
              "Balance query fixture initializes");
      Append_Initial_Policy (Test_Dir, "LOCUS rent" & ASCII.LF);

      --  Initial household has cash & bank in ZERO-ORIGIN, cash & bank & food in ROLES
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Balance_View := Execute (Paths);
      begin
         Assert (View.Status = Query_Complete, "Initial balance query succeeds");
         Assert (View.Total_Known_Count = 2, "Initial known coordinates count is 2 (cash, bank)");
      end;

      --  Record 3 movements
      --  1. cash -> food 1000 on 2026-09-10
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Prop  : constant Proposal_Result :=
           Propose
             (Paths,
              (From_Locus  => (Token => Make_Token ("cash")),
               To_Locus    => (Token => Make_Token ("food")),
               Measure     => (Token => Make_Token ("jpy")),
               Amount      => 1_000,
               Valid_On    => Make_Date (2026, 9, 10),
               Description => Make_Token ("Lunch 1")));
      begin
         Assert (Commit (Prop.Proposal).Success, "Movement 1 commits");
      end;

      --  2. bank -> rent 50000 on 2026-09-15
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Prop  : constant Proposal_Result :=
           Propose
             (Paths,
              (From_Locus  => (Token => Make_Token ("bank")),
               To_Locus    => (Token => Make_Token ("rent")),
               Measure     => (Token => Make_Token ("jpy")),
               Amount      => 50_000,
               Valid_On    => Make_Date (2026, 9, 15),
               Description => Make_Token ("Rent September")));
      begin
         Assert (Commit (Prop.Proposal).Success, "Movement 2 commits");
      end;

      --  3. cash -> food 200 on 2026-09-20
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         Prop  : constant Proposal_Result :=
           Propose
             (Paths,
              (From_Locus  => (Token => Make_Token ("cash")),
               To_Locus    => (Token => Make_Token ("food")),
               Measure     => (Token => Make_Token ("jpy")),
               Amount      => 200,
               Valid_On    => Make_Date (2026, 9, 20),
               Description => Make_Token ("Coffee")));
      begin
         Assert (Commit (Prop.Proposal).Success, "Movement 3 commits");
      end;

      --  Execute Balance_Query across all coordinates
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Balance_View := Execute (Paths, (Scope => Scope_All, Has_As_Of => False, As_Of_Date => (2026, 1, 1)));

         function Find_Row (Locus : String) return Balance_Row is
         begin
            for I in 1 .. View.Row_Count loop
               if View.Rows (I).Locus.Value (1 .. View.Rows (I).Locus.Length) = Locus then
                  return View.Rows (I);
               end if;
            end loop;
            return Empty_Balance_Row;
         end Find_Row;

         Cash_Row : constant Balance_Row := Find_Row ("cash");
         Bank_Row : constant Balance_Row := Find_Row ("bank");
         Food_Row : constant Balance_Row := Find_Row ("food");
         Rent_Row : constant Balance_Row := Find_Row ("rent");
      begin
         Assert (View.Status = Query_Complete, "Balance query is complete");
         Assert (View.Snapshot.Kind = Snapshot_Versioned, "Snapshot is versioned");
         Assert (View.Total_Known_Count = 2, "Total known count is 2");
         Assert (View.Total_Unknown_Count = 2, "Total unknown count is 2 (food, rent)");

         --  cash: -1000 + -200 = -1200, Known Zero, Role_Asset
         Assert (Cash_Row.Amount = -1_200, "cash balance is -1200");
         Assert (Cash_Row.Epistemic_Status = Status_Known_Zero, "cash is Known Zero");
         Assert (Cash_Row.Has_Role and then Cash_Row.Role = Role_Asset, "cash role is Asset");
         Assert (Cash_Row.Posting_Count = 2, "cash has 2 postings");

         --  bank: -50000, Known Zero, Role_Asset
         Assert (Bank_Row.Amount = -50_000, "bank balance is -50000");
         Assert (Bank_Row.Epistemic_Status = Status_Known_Zero, "bank is Known Zero");
         Assert (Bank_Row.Has_Role and then Bank_Row.Role = Role_Asset, "bank role is Asset");

         --  food: +1200, Unknown Origin (expense has no zero-origin)
         Assert (Food_Row.Amount = 1_200, "food balance is +1200");
         Assert (Food_Row.Epistemic_Status = Status_Unknown_Origin, "food is Unknown Origin");
         Assert (Food_Row.Has_Role and then Food_Row.Role = Role_Expense, "food role is Expense");

         --  rent: +50000, Unknown Origin
         Assert (Rent_Row.Amount = 50_000, "rent balance is +50000");
         Assert (Rent_Row.Epistemic_Status = Status_Unknown_Origin, "rent is Unknown Origin");

         --  Deterministic ordering: Assets appear before Expenses
         declare
            First_Row : constant Balance_Row := View.Rows (1);
            Last_Row  : constant Balance_Row := View.Rows (View.Row_Count);
         begin
            Assert (First_Row.Has_Role and then First_Row.Role = Role_Asset, "First row is an Asset");
            Assert (not Last_Row.Has_Role, "Last row has unassigned role");
         end;
      end;

      --  Scope filtering: Scope_Known_Only
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Balance_View :=
           Execute (Paths, (Scope => Scope_Known_Only, Has_As_Of => False, As_Of_Date => (2026, 1, 1)));
      begin
         Assert (View.Row_Count = 2, "Scope_Known_Only returns exactly 2 rows");
         for I in 1 .. View.Row_Count loop
            Assert (View.Rows (I).Epistemic_Status = Status_Known_Zero,
                    "Row in Scope_Known_Only has Status_Known_Zero");
         end loop;
      end;

      --  Scope filtering: Scope_Unknown_Only
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Balance_View :=
           Execute (Paths, (Scope => Scope_Unknown_Only, Has_As_Of => False, As_Of_Date => (2026, 1, 1)));
      begin
         Assert (View.Row_Count = 2, "Scope_Unknown_Only returns exactly 2 rows");
         for I in 1 .. View.Row_Count loop
            Assert (View.Rows (I).Epistemic_Status = Status_Unknown_Origin,
                    "Row in Scope_Unknown_Only has Status_Unknown_Origin");
         end loop;
      end;

      --  As-of date filtering (as of 2026-09-12: only movement 1 was posted)
      declare
         Paths : constant Path_Config := Resolve_Paths (Test_Dir);
         View  : constant Balance_View :=
           Execute (Paths, (Scope => Scope_All, Has_As_Of => True, As_Of_Date => Make_Date (2026, 9, 12)));

         function Find_Row (Locus : String) return Balance_Row is
         begin
            for I in 1 .. View.Row_Count loop
               if View.Rows (I).Locus.Value (1 .. View.Rows (I).Locus.Length) = Locus then
                  return View.Rows (I);
               end if;
            end loop;
            return Empty_Balance_Row;
         end Find_Row;
      begin
         Assert (Find_Row ("cash").Amount = -1_000, "cash balance as of 09-12 is -1000");
         Assert (Find_Row ("food").Amount = 1_000, "food balance as of 09-12 is +1000");
         Assert (Find_Row ("bank").Amount = 0, "bank balance as of 09-12 is 0");
      end;

      --  Supersession exclusion: Correct e0001 (cash -1000 -> cash -1500)
      declare
         Paths    : constant Path_Config := Resolve_Paths (Test_Dir);
         Corr_Int : constant Correction_Intent :=
           (Target_Id   => Make_Token ("e0001"),
            From_Locus  => (Token => Make_Token ("cash")),
            To_Locus    => (Token => Make_Token ("food")),
            Measure     => (Token => Make_Token ("jpy")),
            Amount      => 1_500,
            Valid_On    => Make_Date (2026, 9, 10),
            Description => Make_Token ("Revised Lunch 1"));
         Prop     : constant Proposal_Result := Propose_Correction (Paths, Corr_Int);
      begin
         Assert (Commit (Prop.Proposal).Success, "Correction commits");

         declare
            After_Paths : constant Path_Config := Resolve_Paths (Test_Dir);
            View        : constant Balance_View := Execute (After_Paths);

            function Find_Row (Locus : String) return Balance_Row is
            begin
               for I in 1 .. View.Row_Count loop
                  if View.Rows (I).Locus.Value (1 .. View.Rows (I).Locus.Length) = Locus then
                     return View.Rows (I);
                  end if;
               end loop;
               return Empty_Balance_Row;
            end Find_Row;
         begin
            --  e0001 (-1000) is superseded!
            --  Only e0004 (-1500) and e0003 (-200) count -> -1700!
            Assert (Find_Row ("cash").Amount = -1_700,
                    "Superseded e0001 is excluded from cash balance (-1700)");
            Assert (Find_Row ("food").Amount = 1_700,
                    "Superseded e0001 is excluded from food balance (+1700)");
         end;
      end;

      --  Reject missing path
      declare
         Bad_Paths : Path_Config;
         View      : Balance_View;
      begin
         Bad_Paths.Resolution_Ok := False;
         View := Execute (Bad_Paths);
         Assert (View.Status = Query_Rejected, "Unresolvable paths reject balance query");
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;

end Test_Balance_Query;
