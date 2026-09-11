------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main test runner
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Test_Support;
with Test_Quantity;
with Test_Relation_Command;
with Test_Movement;
with Test_Event;
with Test_Validity;
with Test_Review;
with Test_Initializer;
with Test_Path_Resolver;
with Test_Atomic_Writer;
with Test_HRA_Storage;
with Test_Home_Query;
with Test_Actual_Query;
with Test_Generation_Transaction;
with Test_Movement_Command;
with Test_Transaction_Metadata;
with Test_Scheduled_Facts;
with Test_Scheduled_Query;
with Test_Scheduled_Command;
with Test_Balance_Query;
with Test_Assertion;
with Test_Attention_Command;
with Test_Capacity_Command;
with Test_Policy;
with Test_Statement;

procedure Test_Runner is
begin
   Put_Line ("========================================");
   Put_Line (" HRA-N Unit Test Suite (Distilled HRA)");
   Put_Line ("========================================");

   Put_Line ("--> Running Test_Quantity...");
   Test_Quantity.Run;

   Put_Line ("--> Running Test_Relation_Command...");
   Test_Relation_Command.Run;

   Put_Line ("--> Running Test_Movement...");
   Test_Movement.Run;

   Put_Line ("--> Running Test_Event...");
   Test_Event.Run;

   Put_Line ("--> Running Test_Validity...");
   Test_Validity.Run;

   Put_Line ("--> Running Test_Review...");
   Test_Review.Run;

   Put_Line ("--> Running Test_Initializer...");
   Test_Initializer.Run;

   Put_Line ("--> Running Test_Path_Resolver...");
   Test_Path_Resolver.Run;

   Put_Line ("--> Running Test_Atomic_Writer...");
   Test_Atomic_Writer.Run;

   Put_Line ("--> Running Test_HRA_Storage...");
   Test_HRA_Storage.Run;

   Put_Line ("--> Running Test_Home_Query...");
   Test_Home_Query.Run;

   Put_Line ("--> Running Test_Actual_Query...");
   Test_Actual_Query.Run;

   Put_Line ("--> Running Test_Generation_Transaction...");
   Test_Generation_Transaction.Run;

   Put_Line ("--> Running Test_Movement_Command...");
   Test_Movement_Command.Run;

   Put_Line ("--> Running Test_Transaction_Metadata...");
   Test_Transaction_Metadata.Run;

   Put_Line ("--> Running Test_Scheduled_Facts...");
   Test_Scheduled_Facts.Run;

   Put_Line ("--> Running Test_Scheduled_Query...");
   Test_Scheduled_Query.Run;

   Put_Line ("--> Running Test_Scheduled_Command...");
   Test_Scheduled_Command.Run;

   Put_Line ("--> Running Test_Balance_Query...");
   Test_Balance_Query.Run;

   Put_Line ("--> Running Test_Assertion...");
   Test_Assertion.Run;

   Put_Line ("--> Running Test_Capacity_Command...");
   Test_Capacity_Command.Run;

   Put_Line ("--> Running Test_Attention_Command...");
   Test_Attention_Command.Run;

   Put_Line ("--> Running Test_Policy...");
   Test_Policy.Run;

   Put_Line ("--> Running Test_Statement...");
   Test_Statement.Run;

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
