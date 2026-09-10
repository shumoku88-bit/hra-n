-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Accounting Role & Financial Statement Engine
-------------------------------------------------------------------------------

with Test_Support;                           use Test_Support;
with HRA_N.Core.Types;                       use HRA_N.Core.Types;
with HRA_N.Core.Quantity;                    use HRA_N.Core.Quantity;
with HRA_N.Core.Event;                       use HRA_N.Core.Event;
with HRA_N.Core.Accounting_Role;             use HRA_N.Core.Accounting_Role;
with HRA_N.Storage.Manifest;                 use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;             use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Accounting_Role_Reader;   use HRA_N.Storage.Accounting_Role_Reader;
with HRA_N.Application.Statement;            use HRA_N.Application.Statement;

package body Test_Accounting_Role is

   JPY : constant Measure_Id := (Token => Make_Token ("jpy"));

   function Make_Simple_Event
     (Id_Str     : String;
      From_Locus : String;
      To_Locus   : String;
      Amt        : Quanta_Type) return Event
   is
      Eff_List : Effect_List;
   begin
      Eff_List.Count := 2;
      Eff_List.Values (1) :=
        (Key     => (Token => Make_Token ("k1")),
         Locus   => (Token => Make_Token (From_Locus)),
         Measure => JPY,
         Amount  => (Quanta => -Amt));
      Eff_List.Values (2) :=
        (Key     => (Token => Make_Token ("k2")),
         Locus   => (Token => Make_Token (To_Locus)),
         Measure => JPY,
         Amount  => (Quanta => Amt));
      return Make_Event ((Token => Make_Token (Id_Str)), Eff_List);
   end Make_Simple_Event;

   procedure Run is
      Role_Res : HRA_N.Storage.Accounting_Role_Reader.Read_Result;
      R        : Accounting_Role;
      Found    : Boolean;
   begin
      --  1. Load real accounting-role.loam from loam-data
      Role_Res := Read_Accounting_Role_File ("/Users/user/Projects/moko/loam-data/accounting-role.loam");
      Assert (Role_Res.Success, "Real accounting-role.loam loads successfully");
      Assert_Equal_Int (40, Long_Long_Integer (Entry_Count (Role_Res.Map)), "Loaded exact 40 accounting role mappings");

      --  Verify key canonical account classifications
      Find_Role (Role_Res.Map, (Token => Make_Token ("cash")), R, Found);
      Assert (Found and then R = Role_Asset, "cash is classified as ASSET");

      Find_Role (Role_Res.Map, (Token => Make_Token ("food")), R, Found);
      Assert (Found and then R = Role_Expense, "food is classified as EXPENSE");

      Find_Role (Role_Res.Map, (Token => Make_Token ("debt-friend-k")), R, Found);
      Assert (Found and then R = Role_Liability, "debt-friend-k is classified as LIABILITY");

      Find_Role (Role_Res.Map, (Token => Make_Token ("equity:opening-balances")), R, Found);
      Assert (Found and then R = Role_Equity, "equity:opening-balances is classified as EQUITY");

      Find_Role (Role_Res.Map, (Token => Make_Token ("pension")), R, Found);
      Assert (Found and then R = Role_Income, "pension is classified as INCOME");

      Find_Role (Role_Res.Map, (Token => Make_Token ("unregistered-account")), R, Found);
      Assert (not Found, "Unregistered account is not found in role map");

      --  2. Synthetic Scenario: 100% Mathematical Coherence Test
      declare
         Mock_Events : Event_Vectors.Vector;
         Rep         : Statement_Report;
      begin
         --  Event 1: Opening balance 100,000 JPY from Equity into Cash
         Mock_Events.Append
           (Make_Simple_Event ("ev-1", "equity:opening-balances", "cash", 100_000));

         --  Event 2: Lesson income 250,000 JPY into Cash
         Mock_Events.Append
           (Make_Simple_Event ("ev-2", "lesson-income", "cash", 250_000));

         --  Event 3: Borrow 50,000 JPY from Friend into Cash
         Mock_Events.Append
           (Make_Simple_Event ("ev-3", "debt-friend-k", "cash", 50_000));

         --  Event 4: Spend 30,000 JPY from Cash on Food
         Mock_Events.Append
           (Make_Simple_Event ("ev-4", "cash", "food", 30_000));

         Generate_Report (Mock_Events, Role_Res.Map, Rep);

         Assert_Equal_Int (4, Long_Long_Integer (Rep.Total_Events), "Mock statement aggregated 4 events");
         Assert_Equal_Int (0, Long_Long_Integer (Rep.Unresolved_Count), "0 unresolved accounts in mock scenario");

         --  Verify Assets: cash = 100,000 + 250,000 + 50,000 - 30,000 = 370,000
         Assert_Equal_Int (370_000, Rep.Summary.Total_Assets, "Total Assets is 370,000 JPY");

         --  Verify Liabilities: debt-friend-k = 50,000
         Assert_Equal_Int (50_000, Rep.Summary.Total_Liabilities, "Total Liabilities is 50,000 JPY");

         --  Verify Equity: opening = 100,000
         Assert_Equal_Int (100_000, Rep.Summary.Total_Equity, "Total Equity is 100,000 JPY");

         --  Verify Income: lesson = 250,000
         Assert_Equal_Int (250_000, Rep.Summary.Total_Income, "Total Income is 250,000 JPY");

         --  Verify Expense: food = 30,000
         Assert_Equal_Int (30_000, Rep.Summary.Total_Expense, "Total Expense is 30,000 JPY");

         --  Net Worth = Assets - Liabilities = 370,000 - 50,000 = 320,000
         Assert_Equal_Int (320_000, Net_Worth (Rep.Summary), "Net Worth is 320,000 JPY");

         --  Net Savings = Income - Expense = 250,000 - 30,000 = 220,000
         Assert_Equal_Int (220_000, Net_Savings (Rep.Summary), "Net Savings is 220,000 JPY");

         --  Fundamental Accounting Equation Check
         --  Assets = (Liabilities + Equity) + (Income - Expense)
         --  370,000 = (50,000 + 100,000) + (250,000 - 30,000) = 150,000 + 220,000 = 370,000
         Assert (Is_Coherent (Rep.Summary), "Mock scenario is 100% mathematically coherent");
      end;

      --  3. Real Production Household Authority Projection (588 events)
      declare
         Manifest_Res : constant Read_Manifest_Result :=
           Read_Manifest_File ("/Users/user/Projects/moko/loam-data/movement-authority/CURRENT");
         Event_Full   : constant String :=
           "/Users/user/Projects/moko/loam-data/movement-authority/" &
           Manifest_Res.Manifest (Family_Event).Rel_Path
             (1 .. Manifest_Res.Manifest (Family_Event).Path_Len);
         Event_Res    : constant HRA_N.Storage.Event_Reader.Read_Result :=
           Read_Event_Memory_File (Event_Full);
         Rep          : Statement_Report;
         Imbalance    : Long_Long_Integer;
      begin
         Assert (Manifest_Res.Success, "Real manifest loaded for statement test");
         Assert (Event_Res.Success, "Real event memory loaded for statement test");
         Assert_Equal_Int (588, Long_Long_Integer (Event_Res.Events.Length), "Exact 588 real events loaded");

         Generate_Report (Event_Res.Events, Role_Res.Map, Rep);

         Assert_Equal_Int (588, Long_Long_Integer (Rep.Total_Events), "Statement report aggregated exact 588 real events");
         Assert_Equal_Int (3, Long_Long_Integer (Rep.Unresolved_Count), "Exact 3 historical unclassified accounts detected");

         --  Strict Conservation Invariant:
         --  Assets - ((Liabilities + Equity) + (Income - Expense)) + Unresolved_Quanta = 0
         Imbalance :=
           Rep.Summary.Total_Assets -
           ((Rep.Summary.Total_Liabilities + Rep.Summary.Total_Equity) +
            (Rep.Summary.Total_Income - Rep.Summary.Total_Expense)) +
           Rep.Summary.Unresolved_Quanta;

         Assert_Equal_Int (0, Imbalance, "Universal conservation law holds exactly to 0 quanta across real authority");
      end;

   end Run;

end Test_Accounting_Role;
