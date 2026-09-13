with HRA_N.Application.Budget_Query; use HRA_N.Application.Budget_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with Test_Support; use Test_Support;

package body Test_Budget_Query is
   procedure Run is
      Journal : Journal_Result;
      Policy : Policy_Result;
      View : Budget_View;
      Snap : constant Snapshot_Reference :=
        (Kind => Snapshot_Versioned, Identity => Make_Token ("synthetic"));
      All_Months_Correct : Boolean := True;
   begin
      Journal.Success := True;
      Policy.Success := True;
      --  Exhaust the supported month coordinate space, without filesystem I/O.
      for Y in Year_Type loop
         for M in Month_Type loop
            View := Project_Month (Journal, Policy, Y, M, Snap);
            if Y = Year_Type'Last and then M = Month_Type'Last then
               All_Months_Correct := All_Months_Correct and then
                 View.Status = Query_Rejected;
            else
               All_Months_Correct := All_Months_Correct and then
                 View.Status = Query_Complete and then
                 View.Report.Start_Year = Y and then
                 View.Report.Start_Month = M and then
                 View.Report.Start_Day = 1 and then
                 View.Report.End_Year = (if M = 12 then Y + 1 else Y) and then
                 View.Report.End_Month = (if M = 12 then 1 else M + 1) and then
                 View.Report.End_Day = 1;
            end if;
            All_Months_Correct := All_Months_Correct and then
              View.Snapshot.Kind = Snapshot_Versioned and then
              Equal_Token (View.Snapshot.Identity, Snap.Identity);
         end loop;
      end loop;
      Assert (All_Months_Correct,
              "Every supported month normalizes once or rejects its unrepresentable end");
      View := Project (Journal, Policy, ((2026, 9, 1), (2026, 9, 1)), Snap);
      Assert (View.Status = Query_Rejected, "Empty interval rejects");
      View := Project (Journal, Policy, ((2026, 10, 1), (2026, 9, 1)), Snap);
      Assert (View.Status = Query_Rejected, "Reversed interval rejects");
      View := Project (Journal, Policy, ((2026, 2, 30), (2026, 3, 1)), Snap);
      Assert (View.Status = Query_Rejected, "Invalid start date rejects");
      View := Project (Journal, Policy, ((2026, 2, 1), (2026, 2, 30)), Snap);
      Assert (View.Status = Query_Rejected, "Invalid exclusive end rejects");
      Journal.Success := False;
      View := Project_Month (Journal, Policy, 2026, 9, Snap);
      Assert (View.Status = Query_Rejected, "Failed journal read is not an empty budget");
      Journal.Success := True;
      Policy.Success := False;
      View := Project_Month (Journal, Policy, 2026, 9, Snap);
      Assert (View.Status = Query_Rejected, "Failed policy read is not an empty budget");
   end Run;
end Test_Budget_Query;
