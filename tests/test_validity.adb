-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Validity
-------------------------------------------------------------------------------

with HRA_N.Core.Types;             use HRA_N.Core.Types;
with HRA_N.Core.Validity;          use HRA_N.Core.Validity;
with Test_Support;                 use Test_Support;

package body Test_Validity is

   procedure Run is
      D_Leap     : Date_Type;
      D_Normal   : Date_Type;
      D_Parsed   : Date_Type;
      D_Bad      : Date_Type;
      Ok         : Boolean;
      Found      : Boolean;
      Found_Date : Date_Type;

      Entries : Validity_Entry_List;
   begin
      -- Test 1: Leap year calendar logic
      Assert (Is_Leap_Year (2024), "2024 is a leap year");
      Assert (not Is_Leap_Year (2026), "2026 is NOT a leap year");
      Assert (Is_Leap_Year (2000), "2000 is a leap year (mod 400 = 0)");
      Assert (not Is_Leap_Year (1900), "1900 is NOT a leap year (mod 100 = 0)");

      -- Test 2: Days in month
      Assert_Equal_Int (29, Long_Long_Integer (Days_In_Month (2024, 2)), "Feb 2024 has 29 days");
      Assert_Equal_Int (28, Long_Long_Integer (Days_In_Month (2026, 2)), "Feb 2026 has 28 days");
      Assert_Equal_Int (30, Long_Long_Integer (Days_In_Month (2026, 4)), "Apr 2026 has 30 days");
      Assert_Equal_Int (31, Long_Long_Integer (Days_In_Month (2026, 5)), "May 2026 has 31 days");

      -- Test 3: Date validation
      Assert (Is_Valid_Date (2024, 2, 29), "2024-02-29 is valid");
      Assert (not Is_Valid_Date (2026, 2, 29), "2026-02-29 is invalid (not leap year)");
      Assert (not Is_Valid_Date (2026, 4, 31), "2026-04-31 is invalid (April has 30 days)");

      D_Leap   := Make_Date (2024, 2, 29);
      D_Normal := Make_Date (2026, 4, 5);

      -- Test 4: ISO formatting & parsing round-trip
      Assert (Format_Iso_Date (D_Leap) = "2024-02-29", "Format_Iso_Date(2024-02-29)");
      Assert (Format_Iso_Date (D_Normal) = "2026-04-05", "Format_Iso_Date(2026-04-05)");

      Ok := Parse_Iso_Date ("2026-04-05", D_Parsed);
      Assert (Ok and then Equal_Date (D_Parsed, D_Normal), "Parse_Iso_Date round-trip");

      Ok := Parse_Iso_Date ("2026-02-29", D_Bad);
      Assert (not Ok and then Equal_Date (D_Bad, (Year => 2026, Month => 1, Day => 1)),
              "Parse_Iso_Date rejects 2026-02-29");

      Ok := Parse_Iso_Date ("bad-date-str", D_Bad);
      Assert (not Ok and then Equal_Date (D_Bad, (Year => 2026, Month => 1, Day => 1)),
              "Parse_Iso_Date rejects malformed string");

      -- Test 5: EventId uniqueness invariant
      Entries.Count := 2;
      Entries.Values (1) := (Event_Id => (Token => Make_Token ("e0001")), Valid_On => D_Normal);
      Entries.Values (2) := (Event_Id => (Token => Make_Token ("e0002")), Valid_On => D_Normal);
      Assert (Event_Ids_Are_Unique (Entries), "Unique EventIds accepted in validity memory");

      Entries.Count := 3;
      Entries.Values (3) := (Event_Id => (Token => Make_Token ("e0001")), Valid_On => D_Leap);
      Assert (not Event_Ids_Are_Unique (Entries), "Duplicate EventId rejected (fail-closed)");

      -- Test 6: Memory lookup
      Entries.Count := 2;
      declare
         Mem : constant Validity_Memory := Make_Validity_Memory (Entries);
      begin
         Find_Occurrence_Date (Mem, (Token => Make_Token ("e0001")), Found_Date, Found);
         Assert (Found and then Equal_Date (Found_Date, D_Normal), "Lookup found occurrence date for e0001");

         Find_Occurrence_Date (Mem, (Token => Make_Token ("e9999")), Found_Date, Found);
         Assert (not Found, "Lookup returns Found = False for unknown EventId");
      end;
   end Run;

end Test_Validity;
