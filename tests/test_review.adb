-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Application Review Boundary Implementation
-------------------------------------------------------------------------------

with HRA_N.Core.Validity;        use HRA_N.Core.Validity;
with HRA_N.Application.Review;   use HRA_N.Application.Review;
with Test_Support;               use Test_Support;

package body Test_Review is

   procedure Run is
      Today : constant Date_Type := Make_Date (2026, 9, 10);
      Q     : Review_Query;
      Ok    : Boolean;
   begin
      --  1. Parse "t" query (week)
      Ok := Parse_Query ("t", Today, Q);
      Assert (Ok, "Parse 't' succeeds");
      Assert (Q.Kind = Query_Week, "'t' produces Query_Week");
      Assert (Equal_Date (Q.Ending_Date, Today), "'t' ending date matches today");

      --  2. Parse "u" query (undated)
      Ok := Parse_Query ("u", Today, Q);
      Assert (Ok, "Parse 'u' succeeds");
      Assert (Q.Kind = Query_Undated, "'u' produces Query_Undated");

      --  3. Parse ISO date query (day)
      Ok := Parse_Query ("2026-09-10", Today, Q);
      Assert (Ok, "Parse '2026-09-10' succeeds");
      Assert (Q.Kind = Query_Day, "ISO date produces Query_Day");
      Assert (Equal_Date (Q.Day_Date, Today), "Day matches parsed ISO date");

      --  4. Parse search query (/coffee)
      Ok := Parse_Query ("/coffee", Today, Q);
      Assert (Ok, "Parse '/coffee' succeeds");
      Assert (Q.Kind = Query_Search, "'/text' produces Query_Search");
      Assert (Q.Search_Text (1 .. Q.Search_Len) = "coffee", "Search text matches");

      --  5. Reject invalid queries
      declare
         Dummy_Q : Review_Query;
      begin
         Assert (not Parse_Query ("invalid", Today, Dummy_Q), "Reject invalid query string");
         Assert (not Parse_Query ("2026-02-29", Today, Dummy_Q), "Reject invalid leap day query string");
         Assert (not Parse_Query ("/", Today, Dummy_Q), "Reject bare slash without search term");
      end;
   end Run;

end Test_Review;
