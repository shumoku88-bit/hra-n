------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main test runner
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO; use Ada.Text_IO;
with Test_Support;
with Test_Quantity;
with Test_Relation_Command;
with Test_Movement;
with Test_Event;
with Test_Actual_Bounded_History;
with Test_Actual_Byte_Spans;
with Test_Actual_Replay_Refinement;
with Test_Actual_Reader_Refinement;
with Test_Actual_Writer_Transition;
with Test_Actual_Correction_Transition;
with Test_Actual_Reversal_Transition;
with Test_Scheduled_Creation_Transition;
with Test_Scheduled_Completion_Transition;
with Test_Scheduled_Completion_Protocol;
with Test_Scheduled_Retirement_Transition;
with Test_Scheduled_Replacement_Transition;
with Test_Loam_Actual_Reader;
with Test_Loam_Accounting_Role_Reader;
with Test_Loam_Accounting_Role_Writer;
with Test_Loam_Zero_Origin_Coverage_Reader;
with Test_Loam_Locus_Admission_Reader;
with Test_Loam_Locus_Admission_Writer;
with Test_Loam_Attention_Reader;
with Test_Loam_Actual_Routing_Writer;
with Test_Loam_Actual_Writer;
with Test_Loam_Actual_Correction_Writer;
with Test_Loam_Actual_Reversal_Writer;
with Test_Loam_Actual_Reversal_Refinement;
with Test_Loam_Actual_Correction_Refinement;
with Test_Loam_Actual_Writer_Refinement;
with Test_Loam_Scheduled_Lifecycle_Reader;
with Test_Loam_Scheduled_Creation_Writer;
with Test_Loam_Scheduled_Creation_Refinement;
with Test_Loam_Scheduled_Completion_Writer;
with Test_Loam_Scheduled_Completion_Refinement;
with Test_Loam_Scheduled_Completion_Publisher;
with Test_Loam_Scheduled_Completion_Protocol_Refinement;
with Test_Loam_Scheduled_Retirement_Writer;
with Test_Loam_Scheduled_Retirement_Refinement;
with Test_Loam_Scheduled_Replacement_Writer;
with Test_Loam_Scheduled_Replacement_Refinement;
with Test_Validity;
with Test_Initializer;
with Test_Path_Resolver;
with Test_Atomic_Writer;
with Test_HRA_Storage;
with Test_HRA_Storage_Portable;
with Test_Home_Query;
with Test_Actual_Query;
with Test_Generation_Transaction;
with Test_Movement_Command;
with Test_Canonical_Movement_Command;
with Test_Canonical_Correction_Command;
with Test_Canonical_Authority;
with Test_Transaction_Metadata;
with Test_Scheduled_Facts;
with Test_Scheduled_Query;
with Test_Scheduled_Command;
with Test_Balance_Query;
with Test_Canonical_Balance_Query;
with Test_Canonical_Activity_Query;
with Test_Attention_Command;
with Test_Capacity_Command;
with Test_Loam_Capacity_Writer;
with Test_Budget_Query;
with Test_Policy;
with Test_Statement;
with Test_Daily_Flow_Query;
with Test_MoM_Query;
with Test_Terminal_UTF8;

procedure Test_Runner is
   Matched : Boolean := False;

   function Selected (Name : String) return Boolean is
   begin
      return Ada.Command_Line.Argument_Count = 0
        or else (Ada.Command_Line.Argument_Count = 1
                 and then Ada.Command_Line.Argument (1) = Name);
   end Selected;

   function Legacy_HRA_Data_Available return Boolean is
      Base : constant String := "/Users/user/Projects/moko/hra-data";
   begin
      return Ada.Directories.Exists (Base & "/journal.hra")
        and then Ada.Directories.Exists (Base & "/policy.hra")
        and then Ada.Directories.Exists (Base & "/scheduled.hra");
   end Legacy_HRA_Data_Available;

   procedure Announce (Name : String) is
   begin
      Matched := True;
      Put_Line ("--> Running " & Name & "...");
   end Announce;
begin
   Put_Line ("========================================");
   Put_Line (" HRA-N Unit Test Suite (Distilled HRA)");
   Put_Line ("========================================");

   if Ada.Command_Line.Argument_Count > 1 then
      Put_Line ("Usage: test_runner [SUITE_NAME]");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   if Selected ("Test_Quantity") then
      Announce ("Test_Quantity");
      Test_Quantity.Run;
   end if;

   if Selected ("Test_Relation_Command") then
      Announce ("Test_Relation_Command");
      Test_Relation_Command.Run;
   end if;

   if Selected ("Test_Movement") then
      Announce ("Test_Movement");
      Test_Movement.Run;
   end if;

   if Selected ("Test_Event") then
      Announce ("Test_Event");
      Test_Event.Run;
   end if;

   if Selected ("Test_Actual_Bounded_History") then
      Announce ("Test_Actual_Bounded_History");
      Test_Actual_Bounded_History.Run;
   end if;

   if Selected ("Test_Actual_Byte_Spans") then
      Announce ("Test_Actual_Byte_Spans");
      Test_Actual_Byte_Spans.Run;
   end if;

   if Selected ("Test_Actual_Replay_Refinement") then
      Announce ("Test_Actual_Replay_Refinement");
      Test_Actual_Replay_Refinement.Run;
   end if;

   if Selected ("Test_Actual_Reader_Refinement") then
      Announce ("Test_Actual_Reader_Refinement");
      Test_Actual_Reader_Refinement.Run;
   end if;

   if Selected ("Test_Actual_Writer_Transition") then
      Announce ("Test_Actual_Writer_Transition");
      Test_Actual_Writer_Transition.Run;
   end if;

   if Selected ("Test_Actual_Correction_Transition") then
      Announce ("Test_Actual_Correction_Transition");
      Test_Actual_Correction_Transition.Run;
   end if;

   if Selected ("Test_Actual_Reversal_Transition") then
      Announce ("Test_Actual_Reversal_Transition");
      Test_Actual_Reversal_Transition.Run;
   end if;

   if Selected ("Test_Scheduled_Creation_Transition") then
      Announce ("Test_Scheduled_Creation_Transition");
      Test_Scheduled_Creation_Transition.Run;
   end if;

   if Selected ("Test_Scheduled_Completion_Transition") then
      Announce ("Test_Scheduled_Completion_Transition");
      Test_Scheduled_Completion_Transition.Run;
   end if;

   if Selected ("Test_Scheduled_Completion_Protocol") then
      Announce ("Test_Scheduled_Completion_Protocol");
      Test_Scheduled_Completion_Protocol.Run;
   end if;

   if Selected ("Test_Scheduled_Retirement_Transition") then
      Announce ("Test_Scheduled_Retirement_Transition");
      Test_Scheduled_Retirement_Transition.Run;
   end if;

   if Selected ("Test_Scheduled_Replacement_Transition") then
      Announce ("Test_Scheduled_Replacement_Transition");
      Test_Scheduled_Replacement_Transition.Run;
   end if;

   if Selected ("Test_Loam_Actual_Reader") then
      Announce ("Test_Loam_Actual_Reader");
      Test_Loam_Actual_Reader.Run;
   end if;

   if Selected ("Test_Loam_Actual_Writer") then
      Announce ("Test_Loam_Actual_Writer");
      Test_Loam_Actual_Writer.Run;
   end if;

   if Selected ("Test_Loam_Actual_Correction_Writer") then
      Announce ("Test_Loam_Actual_Correction_Writer");
      Test_Loam_Actual_Correction_Writer.Run;
   end if;

   if Selected ("Test_Loam_Actual_Reversal_Writer") then
      Announce ("Test_Loam_Actual_Reversal_Writer");
      Test_Loam_Actual_Reversal_Writer.Run;
   end if;

   if Selected ("Test_Loam_Actual_Reversal_Refinement") then
      Announce ("Test_Loam_Actual_Reversal_Refinement");
      Test_Loam_Actual_Reversal_Refinement.Run;
   end if;

   if Selected ("Test_Loam_Actual_Correction_Refinement") then
      Announce ("Test_Loam_Actual_Correction_Refinement");
      Test_Loam_Actual_Correction_Refinement.Run;
   end if;

   if Selected ("Test_Loam_Actual_Writer_Refinement") then
      Announce ("Test_Loam_Actual_Writer_Refinement");
      Test_Loam_Actual_Writer_Refinement.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Lifecycle_Reader") then
      Announce ("Test_Loam_Scheduled_Lifecycle_Reader");
      Test_Loam_Scheduled_Lifecycle_Reader.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Creation_Writer") then
      Announce ("Test_Loam_Scheduled_Creation_Writer");
      Test_Loam_Scheduled_Creation_Writer.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Creation_Refinement") then
      Announce ("Test_Loam_Scheduled_Creation_Refinement");
      Test_Loam_Scheduled_Creation_Refinement.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Completion_Writer") then
      Announce ("Test_Loam_Scheduled_Completion_Writer");
      Test_Loam_Scheduled_Completion_Writer.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Completion_Refinement") then
      Announce ("Test_Loam_Scheduled_Completion_Refinement");
      Test_Loam_Scheduled_Completion_Refinement.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Completion_Publisher") then
      Announce ("Test_Loam_Scheduled_Completion_Publisher");
      Test_Loam_Scheduled_Completion_Publisher.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Completion_Protocol_Refinement") then
      Announce ("Test_Loam_Scheduled_Completion_Protocol_Refinement");
      Test_Loam_Scheduled_Completion_Protocol_Refinement.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Retirement_Writer") then
      Announce ("Test_Loam_Scheduled_Retirement_Writer");
      Test_Loam_Scheduled_Retirement_Writer.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Retirement_Refinement") then
      Announce ("Test_Loam_Scheduled_Retirement_Refinement");
      Test_Loam_Scheduled_Retirement_Refinement.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Replacement_Writer") then
      Announce ("Test_Loam_Scheduled_Replacement_Writer");
      Test_Loam_Scheduled_Replacement_Writer.Run;
   end if;

   if Selected ("Test_Loam_Scheduled_Replacement_Refinement") then
      Announce ("Test_Loam_Scheduled_Replacement_Refinement");
      Test_Loam_Scheduled_Replacement_Refinement.Run;
   end if;

   if Selected ("Test_Validity") then
      Announce ("Test_Validity");
      Test_Validity.Run;
   end if;

   if Selected ("Test_Initializer") then
      Announce ("Test_Initializer");
      Test_Initializer.Run;
   end if;

   if Selected ("Test_Path_Resolver") then
      Announce ("Test_Path_Resolver");
      Test_Path_Resolver.Run;
   end if;

   if Selected ("Test_Atomic_Writer") then
      Announce ("Test_Atomic_Writer");
      Test_Atomic_Writer.Run;
   end if;

   if Selected ("Test_HRA_Storage") then
      Announce ("Test_HRA_Storage_Portable");
      Test_HRA_Storage_Portable.Run;
      if Legacy_HRA_Data_Available then
         Put_Line ("--> Running Test_HRA_Storage real-data regression...");
         Test_HRA_Storage.Run;
      else
         Put_Line
           ("--> Skipping optional Test_HRA_Storage real-data regression;"
            & " legacy local household data is not present.");
      end if;
   end if;

   if Selected ("Test_Home_Query") then
      Announce ("Test_Home_Query");
      Test_Home_Query.Run;
   end if;

   if Selected ("Test_Loam_Accounting_Role_Reader") then
      Announce ("Test_Loam_Accounting_Role_Reader");
      Test_Loam_Accounting_Role_Reader.Run;
   end if;

   if Selected ("Test_Loam_Accounting_Role_Writer") then
      Announce ("Test_Loam_Accounting_Role_Writer");
      Test_Loam_Accounting_Role_Writer.Run;
   end if;

   if Selected ("Test_Loam_Zero_Origin_Coverage_Reader") then
      Announce ("Test_Loam_Zero_Origin_Coverage_Reader");
      Test_Loam_Zero_Origin_Coverage_Reader.Run;
   end if;

   if Selected ("Test_Loam_Attention_Reader") then
      Announce ("Test_Loam_Attention_Reader");
      Test_Loam_Attention_Reader.Run;
   end if;
   if Selected ("Test_Loam_Locus_Admission_Reader") then
      Announce ("Test_Loam_Locus_Admission_Reader");
      Test_Loam_Locus_Admission_Reader.Run;
   end if;

   if Selected ("Test_Loam_Locus_Admission_Writer") then
      Announce ("Test_Loam_Locus_Admission_Writer");
      Test_Loam_Locus_Admission_Writer.Run;
   end if;

   if Selected ("Test_Loam_Actual_Routing_Writer") then
      Announce ("Test_Loam_Actual_Routing_Writer");
      Test_Loam_Actual_Routing_Writer.Run;
   end if;

   if Selected ("Test_Actual_Query") then
      Announce ("Test_Actual_Query");
      Test_Actual_Query.Run;
   end if;

   if Selected ("Test_Generation_Transaction") then
      Announce ("Test_Generation_Transaction");
      Test_Generation_Transaction.Run;
   end if;

   if Selected ("Test_Movement_Command") then
      Announce ("Test_Movement_Command");
      Test_Movement_Command.Run;
   end if;

   if Selected ("Test_Canonical_Movement_Command") then
      Announce ("Test_Canonical_Movement_Command");
      Test_Canonical_Movement_Command.Run;
   end if;

   if Selected ("Test_Canonical_Correction_Command") then
      Announce ("Test_Canonical_Correction_Command");
      Test_Canonical_Correction_Command.Run;
   end if;

   if Selected ("Test_Canonical_Authority") then
      Announce ("Test_Canonical_Authority");
      Test_Canonical_Authority.Run;
   end if;

   if Selected ("Test_Transaction_Metadata") then
      Announce ("Test_Transaction_Metadata");
      Test_Transaction_Metadata.Run;
   end if;

   if Selected ("Test_Scheduled_Facts") then
      Announce ("Test_Scheduled_Facts");
      Test_Scheduled_Facts.Run;
   end if;

   if Selected ("Test_Scheduled_Query") then
      Announce ("Test_Scheduled_Query");
      Test_Scheduled_Query.Run;
   end if;

   if Selected ("Test_Scheduled_Command") then
      Announce ("Test_Scheduled_Command");
      Test_Scheduled_Command.Run;
   end if;

   if Selected ("Test_Balance_Query") then
      Announce ("Test_Balance_Query");
      Test_Balance_Query.Run;
   end if;

   if Selected ("Test_Canonical_Balance_Query") then
      Announce ("Test_Canonical_Balance_Query");
      Test_Canonical_Balance_Query.Run;
   end if;

   if Selected ("Test_Canonical_Activity_Query") then
      Announce ("Test_Canonical_Activity_Query");
      Test_Canonical_Activity_Query.Run;
   end if;

   if Selected ("Test_Capacity_Command") then
      Announce ("Test_Capacity_Command");
      Test_Capacity_Command.Run;
   end if;

   if Selected ("Test_Loam_Capacity_Writer") then
      Announce ("Test_Loam_Capacity_Writer");
      Test_Loam_Capacity_Writer.Run;
   end if;

   if Selected ("Test_Budget_Query") then
      Announce ("Test_Budget_Query");
      Test_Budget_Query.Run;
   end if;

   if Selected ("Test_Attention_Command") then
      Announce ("Test_Attention_Command");
      Test_Attention_Command.Run;
   end if;

   if Selected ("Test_Policy") then
      Announce ("Test_Policy");
      Test_Policy.Run;
   end if;

   if Selected ("Test_Daily_Flow_Query") then
      Announce ("Test_Daily_Flow_Query");
      Test_Daily_Flow_Query.Run;
   end if;

   if Selected ("Test_MoM_Query") then
      Announce ("Test_MoM_Query");
      Test_MoM_Query.Run;
   end if;

   if Selected ("Test_Statement") then
      Announce ("Test_Statement");
      Test_Statement.Run;
   end if;

   if Selected ("Test_Terminal_UTF8") then
      Announce ("Test_Terminal_UTF8");
      Test_Terminal_UTF8.Run;
   end if;

   if Ada.Command_Line.Argument_Count = 1 and then not Matched then
      Put_Line ("Unknown test suite: " & Ada.Command_Line.Argument (1));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Put_Line ("========================================");
   Test_Support.Report_Summary
     (if Ada.Command_Line.Argument_Count = 0 then
         "All HRA-N Unit Tests"
      else
         Ada.Command_Line.Argument (1));

   if Test_Support.All_Passed then
      Put_Line ("ALL TESTS PASSED.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Put_Line ("SOME TESTS FAILED!");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Runner;
