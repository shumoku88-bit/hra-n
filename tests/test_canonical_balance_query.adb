with HRA_N.Application.Canonical_Balance_Query;
use HRA_N.Application.Canonical_Balance_Query;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Reader;
with Test_Support; use Test_Support;

package body Test_Canonical_Balance_Query is

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   function Find
     (View    : Balance_View;
      Locus   : String;
      Measure : String) return Natural
   is
   begin
      for I in 1 .. View.Count loop
         if Equal_Token (View.Rows (I).Locus, Make_Token (Locus))
           and then Equal_Token (View.Rows (I).Measure, Make_Token (Measure))
         then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   procedure Run is
      Fixture : constant String :=
        "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
        & "TX" & HT & "e1" & HT & "2026-09-20" & HT & "NODESC" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-100" & NL
        & "EFFECT" & HT & "food" & HT & "jpy" & HT & "100" & NL
        & "ENDTX" & NL
        & "TX" & HT & "e2" & HT & "2026-09-21" & HT & "NODESC" & NL
        & "REPLACES" & HT & "e1" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-120" & NL
        & "EFFECT" & HT & "food" & HT & "jpy" & HT & "120" & NL
        & "ENDTX" & NL
        & "TX" & HT & "e3" & HT & "2026-09-22" & HT & "NODESC" & NL
        & "REVERSAL-OF" & HT & "e2" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "120" & NL
        & "EFFECT" & HT & "food" & HT & "jpy" & HT & "-120" & NL
        & "ENDTX" & NL
        & "TX" & HT & "e4" & HT & "2026-09-23" & HT & "NODESC" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "500" & NL
        & "EFFECT" & HT & "income" & HT & "jpy" & HT & "-500" & NL
        & "ENDTX" & NL;

      Actual : constant
        HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result :=
          HRA_N.Storage.Loam_Actual_Reader.Read_Loam_Actual_Content
            (Fixture);
      View : constant Balance_View := Project (Actual);
      Cash : constant Natural := Find (View, "cash", "jpy");
      Food : constant Natural := Find (View, "food", "jpy");
      Income : constant Natural := Find (View, "income", "jpy");
   begin
      Assert (Actual.Success, "canonical balance fixture admits");
      Assert (View.Success, "canonical balance projection succeeds");
      Assert_Equal_Int
        (4, Long_Long_Integer (View.Physical_Event_Count),
         "all physical Events remain visible to projection");
      Assert_Equal_Int
        (3, Long_Long_Integer (View.Active_Event_Count),
         "replacement removes exactly the superseded Event from projection");
      Assert_Equal_Int
        (1, Long_Long_Integer (View.Superseded_Event_Count),
         "superseded count records replacement topology");

      Assert (Cash > 0 and then Food > 0 and then Income > 0,
              "all touched canonical coordinates are retained");

      Assert_Equal_Int
        (620, View.Rows (Cash).Inflow,
         "cash gross inflow includes reversal and later movement");
      Assert_Equal_Int
        (120, View.Rows (Cash).Outflow,
         "cash gross outflow excludes superseded original");
      Assert_Equal_Int
        (500, View.Rows (Cash).Net,
         "cash net follows replacement plus physical reversal semantics");

      Assert_Equal_Int
        (0, View.Rows (Food).Net,
         "replacement and reversal cancel food coordinate exactly");
      Assert_Equal_Int
        (-500, View.Rows (Income).Net,
         "independent active movement remains visible");

      Assert
        (View.Rows (1).Locus.Value (1 .. View.Rows (1).Locus.Length)
         <= View.Rows (2).Locus.Value (1 .. View.Rows (2).Locus.Length),
         "canonical balance rows have deterministic lexical presentation");
   end Run;

end Test_Canonical_Balance_Query;
