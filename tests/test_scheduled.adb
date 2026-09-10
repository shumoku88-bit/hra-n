-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Scheduled Movement Lifecycle & Atomic Completion
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Directories;
with GNAT.OS_Lib;

with Test_Support;                          use Test_Support;
with HRA_N.Core.Types;                      use HRA_N.Core.Types;
with HRA_N.Core.Validity;                   use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled;                  use HRA_N.Core.Scheduled;
with HRA_N.Storage.Scheduled_Reader;        use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Application.Scheduled_Publisher; use HRA_N.Application.Scheduled_Publisher;
with HRA_N.Application.Doctor;              use HRA_N.Application.Doctor;

package body Test_Scheduled is

   Sandbox_Dir   : constant String := "/tmp/hra_n_test_scheduled";
   Sandbox_Auth  : constant String := Sandbox_Dir & "/movement-authority";
   Sandbox_Sched : constant String := Sandbox_Dir & "/scheduled.loam";
   function Source_Auth return String is (Real_Data_Dir & "/movement-authority");
   function Source_Sched return String is (Real_Data_Dir & "/scheduled.loam");

   procedure Setup_Sandbox is
      Success : Boolean;
      Args    : GNAT.OS_Lib.Argument_List (1 .. 3);
   begin
      if Ada.Directories.Exists (Sandbox_Dir) then
         Args (1) := new String'("-rf");
         Args (2) := new String'(Sandbox_Dir);
         GNAT.OS_Lib.Spawn
           (Program_Name => "/bin/rm",
            Args         => Args (1 .. 2),
            Success      => Success);
         GNAT.OS_Lib.Free (Args (1));
         GNAT.OS_Lib.Free (Args (2));
      end if;

      Ada.Directories.Create_Path (Sandbox_Dir);

      --  Copy movement-authority
      Ada.Directories.Create_Path (Sandbox_Auth);
      Args (1) := new String'("-R");
      Args (2) := new String'(Source_Auth & "/");
      Args (3) := new String'(Sandbox_Auth);
      GNAT.OS_Lib.Spawn
        (Program_Name => "/bin/cp",
         Args         => Args (1 .. 3),
         Success      => Success);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      GNAT.OS_Lib.Free (Args (3));

      --  Copy scheduled.loam
      Ada.Directories.Copy_File (Source_Sched, Sandbox_Sched);
   end Setup_Sandbox;

   procedure Run is
   begin
      if not Real_Data_Available then
         Ada.Text_IO.Put_Line ("    [SKIP] Real scheduled data not present (standalone CI mode)");
         return;
      end if;

      declare
         Path : constant String := Source_Sched;
         Res  : constant Read_Scheduled_Result := Read_Scheduled_File (Path);
      begin
         if not Res.Success then
            Ada.Text_IO.Put_Line ("Read_Scheduled_File failed at line " &
                                  Natural'Image (Res.Error_Line) & ": " &
                                  Res.Error_Reason (1 .. Res.Error_Len));
         end if;

      --  1. File load and parse
      Assert (Res.Success, "Real scheduled.loam loads successfully");
      Assert_Equal_Int (13, Long_Long_Integer (Res.Lifecycle.Sched_Count), "Loaded exact 13 scheduled occurrences");
      Assert_Equal_Int (2, Long_Long_Integer (Res.Lifecycle.Comp_Count), "Loaded exact 2 completion records");
      Assert_Equal_Int (0, Long_Long_Integer (Res.Lifecycle.Ret_Count), "Loaded exact 0 retirement records");
      Assert_Equal_Int (0, Long_Long_Integer (Res.Lifecycle.Repl_Count), "Loaded exact 0 replacement records");

      --  2. Open-world predicates
      declare
         S1  : constant Scheduled_Id := (Token => Make_Token ("scheduled-1"));
         S2  : constant Scheduled_Id := (Token => Make_Token ("scheduled-2"));
         S3  : constant Scheduled_Id := (Token => Make_Token ("scheduled-3"));
         S10 : constant Scheduled_Id := (Token => Make_Token ("scheduled-10"));
      begin
         Assert (Is_Completed (Res.Lifecycle, S1), "scheduled-1 is completed");
         Assert (Is_Completed (Res.Lifecycle, S2), "scheduled-2 is completed");
         Assert (not Is_Completed (Res.Lifecycle, S3), "scheduled-3 is NOT completed");
         Assert (not Is_Completed (Res.Lifecycle, S10), "scheduled-10 is NOT completed");

         Assert (not Is_Current_Open (Res.Lifecycle, S1), "scheduled-1 is NOT current-open");
         Assert (not Is_Current_Open (Res.Lifecycle, S2), "scheduled-2 is NOT current-open");
         Assert (Is_Current_Open (Res.Lifecycle, S3), "scheduled-3 IS current-open");
         Assert (Is_Current_Open (Res.Lifecycle, S10), "scheduled-10 IS current-open");
      end;

      --  3. Spot check occurrence data (scheduled-3: 2026-09-15 smbc -3000, gpt-plus 3000)
      declare
         S3     : constant Scheduled_Id := (Token => Make_Token ("scheduled-3"));
         Lookup : constant Lookup_Result := Find_Occurrence (Res.Lifecycle, S3);
      begin
         Assert (Lookup.Found, "scheduled-3 occurrence found in memory");
         Assert_Equal_Int (2026, Long_Long_Integer (Lookup.Item.Expected_Day.Year), "scheduled-3 year is 2026");
         Assert_Equal_Int (9, Long_Long_Integer (Lookup.Item.Expected_Day.Month), "scheduled-3 month is 9");
         Assert_Equal_Int (15, Long_Long_Integer (Lookup.Item.Expected_Day.Day), "scheduled-3 day is 15");
         Assert_Equal_Int (2, Long_Long_Integer (Lookup.Item.Changes.Count), "scheduled-3 has 2 changes");
         Assert_Equal_Int (-3000, Long_Long_Integer (Lookup.Item.Changes.Values (1).Amount), "change 1 is -3000");
         Assert_Equal_Int (3000, Long_Long_Integer (Lookup.Item.Changes.Values (2).Amount), "change 2 is +3000");
      end;

      --  4. Count all open occurrences
      declare
         Open_Count : Natural := 0;
      begin
         for I in 1 .. Res.Lifecycle.Sched_Count loop
            if Is_Current_Open (Res.Lifecycle, Res.Lifecycle.Sched_Items (I).Id) then
               Open_Count := Open_Count + 1;
            end if;
         end loop;
         Assert_Equal_Int (11, Long_Long_Integer (Open_Count), "Exact 11 scheduled occurrences are currently open");
      end;

      --  5. Sandbox integration test: Atomic completion of scheduled-3
      Setup_Sandbox;

      declare
         S3      : constant Scheduled_Id := (Token => Make_Token ("scheduled-3"));
         Pub_Res : constant Scheduled_Publish_Result :=
           Complete_Scheduled_Movement
             (Scheduled_Path => Sandbox_Sched,
              Authority_Dir  => Sandbox_Auth,
              Target_Id      => S3,
              Valid_On       => (Year => 2026, Month => 9, Day => 15),
              Description    => "OpenAI ChatGPT Plus");
      begin
         Assert (Pub_Res.Success, "scheduled-3 completion succeeds");
         Assert (Pub_Res.Event_Id_Str (1 .. Pub_Res.Event_Id_Len) = "scheduled-completion:scheduled-3",
                 "EventId matches exact scheduled-completion:scheduled-3 specification");
      end;

      --  6. Verify updated scheduled lifecycle state
      declare
         S3   : constant Scheduled_Id := (Token => Make_Token ("scheduled-3"));
         Res2 : constant Read_Scheduled_Result := Read_Scheduled_File (Sandbox_Sched);
      begin
         Assert (Res2.Success, "Reloading updated scheduled.loam succeeds");
         Assert_Equal_Int (13, Long_Long_Integer (Res2.Lifecycle.Sched_Count), "Scheduled count remains 13");
         Assert_Equal_Int (3, Long_Long_Integer (Res2.Lifecycle.Comp_Count), "Completion count incremented to 3");
         Assert (Is_Completed (Res2.Lifecycle, S3), "scheduled-3 is now completed");
         Assert (not Is_Current_Open (Res2.Lifecycle, S3), "scheduled-3 is no longer current-open");

         --  Verify pending count decreased to 10
         declare
            Open_Count : Natural := 0;
         begin
            for I in 1 .. Res2.Lifecycle.Sched_Count loop
               if Is_Current_Open (Res2.Lifecycle, Res2.Lifecycle.Sched_Items (I).Id) then
                  Open_Count := Open_Count + 1;
               end if;
            end loop;
            Assert_Equal_Int (10, Long_Long_Integer (Open_Count), "Open occurrences decreased from 11 to 10");
         end;
      end;

      --  7. Fail-closed: Duplicate completion must be safely rejected
      declare
         S3      : constant Scheduled_Id := (Token => Make_Token ("scheduled-3"));
         Dup_Res : constant Scheduled_Publish_Result :=
           Complete_Scheduled_Movement
             (Scheduled_Path => Sandbox_Sched,
              Authority_Dir  => Sandbox_Auth,
              Target_Id      => S3,
              Valid_On       => (Year => 2026, Month => 9, Day => 15));
      begin
         Assert (not Dup_Res.Success, "Duplicate completion safely rejected (fail-closed)");
      end;

      --  8. Fail-closed: Non-existent scheduled ID must be rejected
      declare
         Unknown_Id  : constant Scheduled_Id := (Token => Make_Token ("scheduled-999"));
         Unknown_Res : constant Scheduled_Publish_Result :=
           Complete_Scheduled_Movement
             (Scheduled_Path => Sandbox_Sched,
              Authority_Dir  => Sandbox_Auth,
              Target_Id      => Unknown_Id,
              Valid_On       => (Year => 2026, Month => 9, Day => 15));
      begin
         Assert (not Unknown_Res.Success, "Non-existent scheduled ID rejected");
      end;

      --  9. Total System Health Verification: Doctor audit of post-completion authority
      declare
         Doc_Report : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => Sandbox_Auth,
            Coverage_Path => Real_Data_Dir & "/zero-origin-coverage.loam",
            Report        => Doc_Report,
            Quiet         => True);
         Assert (Doc_Report.Overall_Healthy, "Sandbox authority remains 100% HEALTHY after scheduled completion");
         Assert_Equal_Int (589, Long_Long_Integer (Doc_Report.Total_Events), "Total events incremented to 589");
         Assert_Equal_Int (589, Long_Long_Integer (Doc_Report.Total_Validity), "Total validity facts incremented to 589");
         Assert_Equal_Int (589, Long_Long_Integer (Doc_Report.Total_Descriptions), "Total descriptions incremented to 589");
      end;

      --  10. Add new scheduled obligation: Fail-closed on unadmitted locus
      declare
         Bad_Res : constant Scheduled_Mutation_Result :=
           Add_Scheduled_Obligation
             (Scheduled_Path => Sandbox_Sched,
              Authority_Dir  => Sandbox_Auth,
              From_Locus     => "smbc",
              To_Locus       => "crypto_unadmitted",
              Amount         => 1000,
              Valid_On       => (Year => 2026, Month => 10, Day => 20));
      begin
         Assert (not Bad_Res.Success, "Unadmitted locus rejected in scheduled add");
      end;

      --  11. Add new scheduled obligation: Success with auto-allocated sequential ID
      declare
         Add_Res : constant Scheduled_Mutation_Result :=
           Add_Scheduled_Obligation
             (Scheduled_Path => Sandbox_Sched,
              Authority_Dir  => Sandbox_Auth,
              From_Locus     => "smbc",
              To_Locus       => "wifi",
              Amount         => 5000,
              Valid_On       => (Year => 2026, Month => 10, Day => 20));
      begin
         Assert (Add_Res.Success, "Adding scheduled obligation succeeds");
         Assert (Add_Res.Target_Str (1 .. Add_Res.Target_Len) = "scheduled-14",
                 "Allocated next sequential ID scheduled-14");

         --  Verify reloaded lifecycle has 14 scheduled items and scheduled-14 is open
         declare
            Res3 : constant Read_Scheduled_Result := Read_Scheduled_File (Sandbox_Sched);
            S14  : constant Scheduled_Id := (Token => Make_Token ("scheduled-14"));
         begin
            Assert (Res3.Success, "Reloading scheduled file after add succeeds");
            Assert_Equal_Int (14, Long_Long_Integer (Res3.Lifecycle.Sched_Count), "Scheduled count incremented to 14");
            Assert (Is_Current_Open (Res3.Lifecycle, S14), "scheduled-14 is current-open");
         end;
      end;

      --  12. Retire scheduled obligation: Fail-closed on non-open item
      declare
         S1         : constant Scheduled_Id := (Token => Make_Token ("scheduled-1"));
         Bad_Retire : constant Scheduled_Mutation_Result :=
           Retire_Scheduled_Obligation
             (Scheduled_Path => Sandbox_Sched,
              Target_Id      => S1);
      begin
         Assert (not Bad_Retire.Success, "Retiring already-completed obligation rejected");
      end;

      --  13. Retire scheduled obligation: Success
      declare
         S14     : constant Scheduled_Id := (Token => Make_Token ("scheduled-14"));
         Ret_Res : constant Scheduled_Mutation_Result :=
           Retire_Scheduled_Obligation
             (Scheduled_Path => Sandbox_Sched,
              Target_Id      => S14);
      begin
         Assert (Ret_Res.Success, "Retiring open obligation succeeds");

         --  Verify reloaded lifecycle has 1 retirement record and scheduled-14 is no longer open
         declare
            Res4 : constant Read_Scheduled_Result := Read_Scheduled_File (Sandbox_Sched);
         begin
            Assert (Res4.Success, "Reloading scheduled file after retire succeeds");
            Assert_Equal_Int (1, Long_Long_Integer (Res4.Lifecycle.Ret_Count), "Retirement count incremented to 1");
            Assert (Is_Retired (Res4.Lifecycle, S14), "scheduled-14 is retired");
            Assert (not Is_Current_Open (Res4.Lifecycle, S14), "scheduled-14 is no longer open");
         end;

         --  Double retirement rejected
         declare
            Dup_Ret : constant Scheduled_Mutation_Result :=
              Retire_Scheduled_Obligation
                (Scheduled_Path => Sandbox_Sched,
                 Target_Id      => S14);
         begin
            Assert (not Dup_Ret.Success, "Duplicate retirement safely rejected (fail-closed)");
         end;
      end;
      end;

   end Run;

end Test_Scheduled;
