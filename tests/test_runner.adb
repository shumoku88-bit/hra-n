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
with Test_Admission;
with Test_Publisher;
with Test_Doctor;
with Test_Initializer;
with Test_Scheduled;
with Test_Path_Resolver;
with Test_Actual_Reversal;
with Test_Accounting_Role;
with Test_Budget_Window;
with Test_Catalog;
with Test_Relation;
with Test_Scheduled_Routing;
with Test_Scheduled_Commitment;
with Test_Correction;
with Test_Atomic_Writer;
with Test_Authority_Transaction;
with Test_Correction_Publisher;
with Test_Actual_Validity_Publisher;
with Test_Scheduled_Balance;

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

   Put_Line ("--> Running Test_Admission...");
   Test_Admission.Run;

   Put_Line ("--> Running Test_Publisher...");
   Test_Publisher.Run;

   Put_Line ("--> Running Test_Doctor...");
   Test_Doctor.Run;

   Put_Line ("--> Running Test_Initializer...");
   Test_Initializer.Run;

   Put_Line ("--> Running Test_Scheduled...");
   Test_Scheduled.Run;

   Put_Line ("--> Running Test_Path_Resolver...");
   Test_Path_Resolver.Run;

   Put_Line ("--> Running Test_Actual_Reversal...");
   Test_Actual_Reversal.Run;

   Put_Line ("--> Running Test_Accounting_Role...");
   Test_Accounting_Role.Run;

   Put_Line ("--> Running Test_Budget_Window...");
   Test_Budget_Window.Run;

   Put_Line ("--> Running Test_Catalog...");
   Test_Catalog.Run;

   Put_Line ("--> Running Test_Relation...");
   Test_Relation.Run;

   Put_Line ("--> Running Test_Scheduled_Routing...");
   Test_Scheduled_Routing.Run;

   Put_Line ("--> Running Test_Scheduled_Commitment...");
   Test_Scheduled_Commitment.Run;

   Put_Line ("--> Running Test_Correction...");
   Test_Correction.Run;

   Put_Line ("--> Running Test_Atomic_Writer...");
   Test_Atomic_Writer.Run;

   Put_Line ("--> Running Test_Authority_Transaction...");
   Test_Authority_Transaction.Run;

   Put_Line ("--> Running Test_Correction_Publisher...");
   Test_Correction_Publisher.Run;

   Put_Line ("--> Running Test_Actual_Validity_Publisher...");
   Test_Actual_Validity_Publisher.Run;

   Put_Line ("--> Running Test_Scheduled_Balance...");
   Test_Scheduled_Balance.Run;

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
