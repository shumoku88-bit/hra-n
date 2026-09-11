-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Policy
-------------------------------------------------------------------------------

with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Window_Policy; use HRA_N.Core.Window_Policy;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Initializer; use HRA_N.Application.Initializer;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Policy_Query; use HRA_N.Application.Policy_Query;
with HRA_N.Application.Policy_Command; use HRA_N.Application.Policy_Command;

package body Test_Policy is

   Test_Dir : constant String := "/tmp/hra_n_test_policy";

   procedure Test_Role_Laws is
      Map : Role_Map;
   begin
      Assert (All_Role_Laws_Hold (Map), "Empty role map is sound");

      --  1. Add r0001: cash ASSET
      Map.Count := 1;
      Map.Entries (1) :=
        (Id             => Make_Token ("r0001"),
         Locus          => (Token => Make_Token ("cash")),
         Role           => Role_Asset,
         Effective_From => Make_Date (2026, 1, 1),
         Has_Replaces   => False,
         Replaces       => (Length => 0, Value => [others => ' ']));
      Assert (All_Role_Laws_Hold (Map), "Single role is sound");

      --  2. Duplicate ID fails
      declare
         Bad : Role_Map := Map;
      begin
         Bad.Count := 2;
         Bad.Entries (2) :=
           (Id             => Make_Token ("r0001"),
            Locus          => (Token => Make_Token ("bank")),
            Role           => Role_Asset,
            Effective_From => Make_Date (2026, 1, 1),
            Has_Replaces   => False,
            Replaces       => (Length => 0, Value => [others => ' ']));
         Assert (not Identities_Are_Unique (Bad), "Duplicate role ID fails closed");
         Assert (not All_Role_Laws_Hold (Bad), "Duplicate role ID is not sound");
      end;

      --  3. Unknown replacement target fails
      declare
         Bad : Role_Map := Map;
      begin
         Bad.Count := 2;
         Bad.Entries (2) :=
           (Id             => Make_Token ("r0002"),
            Locus          => (Token => Make_Token ("cash")),
            Role           => Role_Asset,
            Effective_From => Make_Date (2026, 6, 1),
            Has_Replaces   => True,
            Replaces       => Make_Token ("r9999"));
         Assert (not Replacement_Targets_Exist (Bad), "Unknown replacement target fails closed");
         Assert (not All_Role_Laws_Hold (Bad), "Unknown replacement target is not sound");
      end;

      --  4. Cross-locus replacement fails
      declare
         Bad : Role_Map := Map;
      begin
         Bad.Count := 2;
         Bad.Entries (2) :=
           (Id             => Make_Token ("r0002"),
            Locus          => (Token => Make_Token ("food")),
            Role           => Role_Expense,
            Effective_From => Make_Date (2026, 6, 1),
            Has_Replaces   => True,
            Replaces       => Make_Token ("r0001"));
         Assert (not Replacement_Targets_Match_Locus (Bad), "Cross-locus replacement fails closed");
         Assert (not All_Role_Laws_Hold (Bad), "Cross-locus replacement is not sound");
      end;

      --  5. Branching replacement fails (two replacements for r0001)
      declare
         Bad : Role_Map := Map;
      begin
         Bad.Count := 3;
         Bad.Entries (2) :=
           (Id             => Make_Token ("r0002"),
            Locus          => (Token => Make_Token ("cash")),
            Role           => Role_Asset,
            Effective_From => Make_Date (2026, 6, 1),
            Has_Replaces   => True,
            Replaces       => Make_Token ("r0001"));
         Bad.Entries (3) :=
           (Id             => Make_Token ("r0003"),
            Locus          => (Token => Make_Token ("cash")),
            Role           => Role_Liability,
            Effective_From => Make_Date (2026, 7, 1),
            Has_Replaces   => True,
            Replaces       => Make_Token ("r0001"));
         Assert (not Replacements_Are_One_To_One (Bad), "Branching role replacement fails closed");
         Assert (not All_Role_Laws_Hold (Bad), "Branching role replacement is not sound");
      end;

      --  6. Cyclic replacement fails (r1 -> r2 -> r1)
      declare
         Bad : Role_Map;
      begin
         Bad.Count := 2;
         Bad.Entries (1) :=
           (Id             => Make_Token ("r0001"),
            Locus          => (Token => Make_Token ("cash")),
            Role           => Role_Asset,
            Effective_From => Make_Date (2026, 1, 1),
            Has_Replaces   => True,
            Replaces       => Make_Token ("r0002"));
         Bad.Entries (2) :=
           (Id             => Make_Token ("r0002"),
            Locus          => (Token => Make_Token ("cash")),
            Role           => Role_Asset,
            Effective_From => Make_Date (2026, 6, 1),
            Has_Replaces   => True,
            Replaces       => Make_Token ("r0001"));
         Assert (not Replacement_History_Is_Acyclic (Bad), "Cyclic role replacement fails closed");
         Assert (not All_Role_Laws_Hold (Bad), "Cyclic role replacement is not sound");
      end;

      --  7. Conflicting active roles on same locus fails
      declare
         Bad : Role_Map := Map;
      begin
         Bad.Count := 2;
         Bad.Entries (2) :=
           (Id             => Make_Token ("r0002"),
            Locus          => (Token => Make_Token ("cash")),
            Role           => Role_Liability,
            Effective_From => Make_Date (2026, 6, 1),
            Has_Replaces   => False,
            Replaces       => (Length => 0, Value => [others => ' ']));
         Assert (not Active_Roles_Loci_Are_Unique (Bad), "Conflicting active roles fail closed");
         Assert (not All_Role_Laws_Hold (Bad), "Conflicting active roles is not sound");
      end;

      --  8. Valid sequence with replacement and effective dating
      Map.Count := 3;
      Map.Entries (2) :=
        (Id             => Make_Token ("r0002"),
         Locus          => (Token => Make_Token ("food")),
         Role           => Role_Expense,
         Effective_From => Make_Date (2026, 1, 1),
         Has_Replaces   => False,
         Replaces       => (Length => 0, Value => [others => ' ']));
      Map.Entries (3) :=
        (Id             => Make_Token ("r0003"),
         Locus          => (Token => Make_Token ("food")),
         Role           => Role_Asset,
         Effective_From => Make_Date (2026, 9, 1),
         Has_Replaces   => True,
         Replaces       => Make_Token ("r0002"));

      Assert (All_Role_Laws_Hold (Map), "Valid role sequence is sound");
      Assert_Equal_Int (2, Long_Long_Integer (Active_Count (Map)), "Active count is 2 (cash, food)");

      declare
         R     : Accounting_Role;
         Found : Boolean := False;
      begin
         --  As of 2026-06-01 (before replacement), food is EXPENSE
         Find_Role_As_Of (Map, (Token => Make_Token ("food")), Make_Date (2026, 6, 1), R, Found);
         Assert (Found and then R = Role_Expense, "food is EXPENSE as of 2026-06-01");

         --  As of 2026-09-15 (after replacement), food is ASSET
         Find_Role_As_Of (Map, (Token => Make_Token ("food")), Make_Date (2026, 9, 15), R, Found);
         Assert (Found and then R = Role_Asset, "food is ASSET as of 2026-09-15");

         --  Latest active role without date filter is ASSET
         Find_Role (Map, (Token => Make_Token ("food")), R, Found);
         Assert (Found and then R = Role_Asset, "food latest role is ASSET");
      end;
   end Test_Role_Laws;

   procedure Test_Window_Laws is
      Mem : Window_Memory;
      Win : Window_Definition;
      Found : Boolean := False;
   begin
      Assert (Windows_Are_Sound (Mem), "Empty windows are sound");

      --  Add valid window
      Mem.Count := 1;
      Mem.Windows (1) :=
        (Id         => Make_Token ("w0001"),
         Start_Date => Make_Date (2026, 9, 1),
         End_Date   => Make_Date (2026, 10, 1),
         Name       => Make_Token ("September 2026"));
      Assert (Windows_Are_Sound (Mem), "Valid window is sound");

      --  Date_In_Window half-open checks
      Assert (Date_In_Window (Make_Date (2026, 9, 1), Mem.Windows (1)), "Start date is inside window");
      Assert (Date_In_Window (Make_Date (2026, 9, 15), Mem.Windows (1)), "Middle date is inside window");
      Assert (not Date_In_Window (Make_Date (2026, 10, 1), Mem.Windows (1)), "End date is excluded (half-open)");
      Assert (not Date_In_Window (Make_Date (2026, 8, 31), Mem.Windows (1)), "Prior date is excluded");

      --  Find_Window_For_Date
      Find_Window_For_Date (Mem, Make_Date (2026, 9, 20), Win, Found);
      Assert (Found and then Equal_Token (Win.Id, Make_Token ("w0001")), "Found window w0001 for 09-20");

      Find_Window_For_Date (Mem, Make_Date (2026, 10, 15), Win, Found);
      Assert (not Found, "No window covers 10-15");

      --  Invalid window dates (Start >= End) fails
      declare
         Bad : Window_Memory := Mem;
      begin
         Bad.Count := 2;
         Bad.Windows (2) :=
           (Id         => Make_Token ("w0002"),
            Start_Date => Make_Date (2026, 10, 1),
            End_Date   => Make_Date (2026, 9, 1),
            Name       => Make_Token ("Inverted"));
         Assert (not Windows_Are_Sound (Bad), "Inverted window dates fail closed");
      end;

      --  Duplicate window ID fails
      declare
         Bad : Window_Memory := Mem;
      begin
         Bad.Count := 2;
         Bad.Windows (2) :=
           (Id         => Make_Token ("w0001"),
            Start_Date => Make_Date (2026, 10, 1),
            End_Date   => Make_Date (2026, 11, 1),
            Name       => Make_Token ("Duplicate ID"));
         Assert (not Windows_Are_Sound (Bad), "Duplicate window ID fails closed");
      end;
   end Test_Window_Laws;

   procedure Test_Routing_Laws is
      Map     : Routing_Map;
      Purpose : Token_Text;
      Found   : Boolean;
   begin
      Map.Count := 2;
      Map.Entries (1) :=
        (Locus          => (Token => Make_Token ("food")),
         Effective_Kind => Routing_Initial,
         Effective_On   => Make_Date (1900, 1, 1),
         Managed        => True,
         Purpose        => Make_Token ("groceries"));
      Map.Entries (2) :=
        (Locus          => (Token => Make_Token ("food")),
         Effective_Kind => Routing_From_Date,
         Effective_On   => Make_Date (2026, 10, 1),
         Managed        => False,
         Purpose        => (Length => 0, Value => [others => ' ']));
      Assert (Coordinates_Are_Unique (Map),
              "Distinct routing effective coordinates are sound");
      Find_Purpose_As_Of
        (Map, (Token => Make_Token ("food")), Make_Date (2026, 9, 30),
         Purpose, Found);
      Assert (Found and then Equal_Token (Purpose, Make_Token ("groceries")),
              "Initial managed route resolves before transition");
      Find_Purpose_As_Of
        (Map, (Token => Make_Token ("food")), Make_Date (2026, 10, 1),
         Purpose, Found);
      Assert (not Found,
              "Dated unmanaged route suppresses prior managed route");
      Map.Entries (2).Effective_Kind := Routing_Initial;
      Assert (not Coordinates_Are_Unique (Map),
              "Duplicate routing effective coordinate fails closed");
   end Test_Routing_Laws;

   procedure Test_Commands is
      Paths : Path_Config;
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;

      Assert (Initialize_Household (Test_Dir).Success, "Fixture initializes");
      Paths := Resolve_Paths (Test_Dir);

      --  1. Propose and commit new role: crypto ASSET
      declare
         Intent : constant Role_Intent :=
           (Id             => (Length => 0, Value => [others => ' ']),
            Locus          => (Token => Make_Token ("crypto")),
            Role           => Role_Asset,
            Effective_From => Make_Date (2026, 9, 1),
            Has_Replaces   => False,
            Replaces_Id    => (Length => 0, Value => [others => ' ']));
         Prop   : constant Proposal_Result := Propose_Role (Paths, Intent);
         Rec    : Policy_Receipt;
      begin
         Assert (Prop.Success, "Role proposal succeeds");
         Rec := Commit (Prop.Proposal);
         Assert (Rec.Success, "Role commit succeeds");
         Assert (Rec.Snapshot_Id (1 .. Rec.Snapshot_Len) = "g00000002", "Snapshot advances to g00000002");
         Assert (Rec.Primary_Id (1 .. Rec.Primary_Len) = "r0001", "Allocated role ID is r0001");
      end;

      --  Reload paths
      Paths := Resolve_Paths (Test_Dir);

      --  2. Query active roles sees crypto
      declare
         View : constant Role_View := Execute_Role_Query (Paths);
      begin
         Assert (View.Status = Query_Complete, "Role query completes");
         Assert (View.Row_Count >= 1, "Role query contains rows");
         declare
            Found_Crypto : Boolean := False;
         begin
            for I in 1 .. View.Row_Count loop
               if Equal_Token (View.Rows (I).Locus, Make_Token ("crypto")) then
                  Found_Crypto := True;
                  Assert (View.Rows (I).Role = Role_Asset, "crypto is ASSET");
               end if;
            end loop;
            Assert (Found_Crypto, "crypto role found in active view");
         end;
      end;

      --  3. Propose replacement: crypto changes to EXPENSE on 2026-10-01 replacing r0001
      declare
         Intent : constant Role_Intent :=
           (Id             => (Length => 0, Value => [others => ' ']),
            Locus          => (Token => Make_Token ("crypto")),
            Role           => Role_Expense,
            Effective_From => Make_Date (2026, 10, 1),
            Has_Replaces   => True,
            Replaces_Id    => Make_Token ("r0001"));
         Prop   : constant Proposal_Result := Propose_Role (Paths, Intent);
         Rec    : Policy_Receipt;
      begin
         Assert (Prop.Success, "Role replacement proposal succeeds");
         Rec := Commit (Prop.Proposal);
         Assert (Rec.Success, "Role replacement commit succeeds");
         Assert (Rec.Snapshot_Id (1 .. Rec.Snapshot_Len) = "g00000003", "Snapshot advances to g00000003");
         Assert (Rec.Primary_Id (1 .. Rec.Primary_Len) = "r0002", "Allocated role ID is r0002");
      end;

      --  Reload paths
      Paths := Resolve_Paths (Test_Dir);

      --  4. Role query as-of 2026-09-15 sees crypto ASSET, as-of 2026-10-05 sees crypto EXPENSE
      declare
         View_Sep : constant Role_View :=
           Execute_Role_Query (Paths, As_Of => Make_Date (2026, 9, 15), Has_As_Of => True);
         View_Oct : constant Role_View :=
           Execute_Role_Query (Paths, As_Of => Make_Date (2026, 10, 5), Has_As_Of => True);
      begin
         for I in 1 .. View_Sep.Row_Count loop
            if Equal_Token (View_Sep.Rows (I).Locus, Make_Token ("crypto")) then
               Assert (View_Sep.Rows (I).Role = Role_Asset, "crypto as of 09-15 is ASSET");
            end if;
         end loop;

         for I in 1 .. View_Oct.Row_Count loop
            if Equal_Token (View_Oct.Rows (I).Locus, Make_Token ("crypto")) then
               Assert (View_Oct.Rows (I).Role = Role_Expense, "crypto as of 10-05 is EXPENSE");
            end if;
         end loop;
      end;

      --  5. Propose duplicate without replacement fails closed
      declare
         Intent : constant Role_Intent :=
           (Id             => (Length => 0, Value => [others => ' ']),
            Locus          => (Token => Make_Token ("crypto")),
            Role           => Role_Income,
            Effective_From => Make_Date (2026, 11, 1),
            Has_Replaces   => False,
            Replaces_Id    => (Length => 0, Value => [others => ' ']));
         Prop   : constant Proposal_Result := Propose_Role (Paths, Intent);
      begin
         Assert (not Prop.Success, "Duplicate role without replacement fails closed");
      end;

      --  6. Propose branching replacement fails closed (r0001 is already replaced by r0002)
      declare
         Intent : constant Role_Intent :=
           (Id             => (Length => 0, Value => [others => ' ']),
            Locus          => (Token => Make_Token ("crypto")),
            Role           => Role_Income,
            Effective_From => Make_Date (2026, 11, 1),
            Has_Replaces   => True,
            Replaces_Id    => Make_Token ("r0001"));
         Prop   : constant Proposal_Result := Propose_Role (Paths, Intent);
      begin
         Assert (not Prop.Success, "Branching replacement of r0001 fails closed");
      end;

      --  7. Propose and commit Evaluation Window
      declare
         Intent : constant Window_Intent :=
           (Id         => Make_Token ("w0001"),
            Start_Date => Make_Date (2026, 9, 1),
            End_Date   => Make_Date (2026, 10, 1),
            Name       => Make_Token ("September 2026"));
         Prop   : constant Proposal_Result := Propose_Window (Paths, Intent);
         Rec    : Policy_Receipt;
      begin
         Assert (Prop.Success, "Window proposal succeeds");
         Rec := Commit (Prop.Proposal);
         Assert (Rec.Success, "Window commit succeeds");
         Assert (Rec.Snapshot_Id (1 .. Rec.Snapshot_Len) = "g00000004", "Snapshot advances to g00000004");
         Assert (Rec.Primary_Id (1 .. Rec.Primary_Len) = "w0001", "Allocated window ID is w0001");
      end;

      --  Reload paths
      Paths := Resolve_Paths (Test_Dir);

      --  8. Window query sees window
      declare
         View : constant Window_View := Execute_Window_Query (Paths);
      begin
         Assert (View.Status = Query_Complete, "Window query completes");
         Assert (View.Window_Count = 1, "Window query returns 1 window");
         Assert (Equal_Token (View.Windows (1).Id, Make_Token ("w0001")), "Window ID is w0001");
      end;

      --  9. Propose duplicate window fails closed
      declare
         Intent : constant Window_Intent :=
           (Id         => Make_Token ("w0001"),
            Start_Date => Make_Date (2026, 10, 1),
            End_Date   => Make_Date (2026, 11, 1),
            Name       => Make_Token ("Duplicate"));
         Prop   : constant Proposal_Result := Propose_Window (Paths, Intent);
      begin
         Assert (not Prop.Success, "Duplicate window ID fails closed");
      end;

      --  10. Historical Actual routing is proposal-backed and date-aware.
      declare
         Intent : constant Routing_Intent :=
           (Locus          => (Token => Make_Token ("food")),
            Effective_Kind => Routing_Initial,
            Effective_On   => Make_Date (1900, 1, 1),
            Managed        => True,
            Purpose        => Make_Token ("groceries"));
         Prop : constant Proposal_Result := Propose_Routing (Paths, Intent);
         Rec  : Policy_Receipt;
      begin
         Assert (Prop.Success, "Initial managed routing proposes");
         Rec := Commit (Prop.Proposal);
         Assert (Rec.Success, "Initial managed routing commits");
         Assert (Rec.Snapshot_Id (1 .. Rec.Snapshot_Len) = "g00000005",
                 "Routing commit advances snapshot");
         Assert (Commit (Prop.Proposal).Success,
                 "Routing commit retry is idempotent");
      end;
      Paths := Resolve_Paths (Test_Dir);

      declare
         Intent : constant Routing_Intent :=
           (Locus          => (Token => Make_Token ("food")),
            Effective_Kind => Routing_From_Date,
            Effective_On   => Make_Date (2026, 10, 1),
            Managed        => False,
            Purpose        => (Length => 0, Value => [others => ' ']));
         Prop : constant Proposal_Result := Propose_Routing (Paths, Intent);
      begin
         Assert (Prop.Success, "Dated unmanaged routing proposes");
         Assert (Commit (Prop.Proposal).Success,
                 "Dated unmanaged routing commits");
      end;
      Paths := Resolve_Paths (Test_Dir);

      declare
         Sep : constant Routing_View :=
           Execute_Routing_Query (Paths, Make_Date (2026, 9, 30));
         Oct : constant Routing_View :=
           Execute_Routing_Query (Paths, Make_Date (2026, 10, 1));
         Hist : constant Routing_View :=
           Execute_Routing_Query
             (Paths, Make_Date (2026, 10, 1), Include_History => True);
      begin
         Assert (Sep.Status = Query_Complete and then Sep.Row_Count = 1,
                 "Routing query returns September projection");
         Assert (Sep.Rows (1).Managed
                 and then Equal_Token
                   (Sep.Rows (1).Purpose, Make_Token ("groceries")),
                 "Initial route is effective before dated assertion");
         Assert (Oct.Row_Count = 1 and then not Oct.Rows (1).Managed,
                 "Explicit unmanaged assertion is effective on its date");
         Assert (Hist.Row_Count = 2,
                 "Routing history retains both assertions");
      end;

      --  Duplicate coordinates and stale proposals fail closed.
      declare
         Duplicate : constant Routing_Intent :=
           (Locus          => (Token => Make_Token ("food")),
            Effective_Kind => Routing_Initial,
            Effective_On   => Make_Date (1900, 1, 1),
            Managed        => True,
            Purpose        => Make_Token ("other"));
      begin
         Assert (not Propose_Routing (Paths, Duplicate).Success,
                 "Duplicate routing coordinate fails closed");
      end;

      declare
         Stale_Intent : constant Routing_Intent :=
           (Locus          => (Token => Make_Token ("food")),
            Effective_Kind => Routing_From_Date,
            Effective_On   => Make_Date (2026, 11, 1),
            Managed        => True,
            Purpose        => Make_Token ("future"));
         Advance_Intent : constant Routing_Intent :=
           (Locus          => (Token => Make_Token ("misc")),
            Effective_Kind => Routing_Initial,
            Effective_On   => Make_Date (1900, 1, 1),
            Managed        => True,
            Purpose        => Make_Token ("other"));
         Stale : constant Proposal_Result :=
           Propose_Routing (Paths, Stale_Intent);
         Advance : constant Proposal_Result :=
           Propose_Routing (Paths, Advance_Intent);
      begin
         Assert (Stale.Success and then Advance.Success,
                 "Concurrent routing proposals are constructed");
         Assert (Commit (Advance.Proposal).Success,
                 "Advancing routing proposal commits");
         Assert (not Commit (Stale.Proposal).Success,
                 "Stale routing proposal fails closed");
      end;

      --  Cleanup
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
   end Test_Commands;

   procedure Run is
   begin
      Test_Role_Laws;
      Test_Window_Laws;
      Test_Routing_Laws;
      Test_Commands;
   end Run;

end Test_Policy;
