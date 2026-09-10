-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main test runner
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Test_Support;
with Test_Quantity;
with Test_Movement;
with Test_Event;
with Test_Event_Reader;
with Test_Coverage;
with Test_Manifest;
with Test_Validity;
with Test_Description;
with Test_Review;

procedure Test_Runner is
begin
   Put_Line ("========================================");
   Put_Line (" HRA-N Unit Test Suite");
   Put_Line ("========================================");

   Put_Line ("--> Running Test_Quantity...");
   Test_Quantity.Run;

   Put_Line ("--> Running Test_Movement...");
   Test_Movement.Run;

   Put_Line ("--> Running Test_Event...");
   Test_Event.Run;

   Put_Line ("--> Running Test_Event_Reader...");
   Test_Event_Reader.Run;

   Put_Line ("--> Running Test_Coverage...");
   Test_Coverage.Run;

   Put_Line ("--> Running Test_Manifest...");
   Test_Manifest.Run;

   Put_Line ("--> Running Test_Validity...");
   Test_Validity.Run;

   Put_Line ("--> Running Test_Description...");
   Test_Description.Run;

   Put_Line ("--> Running Test_Review...");
   Test_Review.Run;

   Put_Line ("========================================");
   Test_Support.Report_Summary ("All HRA-N Unit Tests");

   if Test_Support.All_Passed then
      Put_Line ("ALL TESTS PASSED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Put_Line ("SOME TESTS FAILED!");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Runner;
