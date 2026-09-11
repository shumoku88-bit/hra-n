with Ada.Directories;
with Ada.Text_IO;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Storage.Scheduled_Journal_Reader;
with Test_Support; use Test_Support;

package body Test_Scheduled_Facts is
   procedure Run is
      Path : constant String := "/tmp/hra_n_test_scheduled_facts.hra";

      procedure Write_Facts (Content : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put (File, Content);
         Ada.Text_IO.Close (File);
      end Write_Facts;

      function Read return HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result is
        (HRA_N.Storage.Scheduled_Journal_Reader.Read_Scheduled_Journal_File (Path));
   begin
      Write_Facts
        ("SCHED s1 2026-10-01 cash:-100 rent:100" & ASCII.LF &
         "SCHED s2 2026-11-01 cash:-100 rent:100" & ASCII.LF &
         "COMPLETE s1 e1" & ASCII.LF);
      declare
         Result : constant HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result := Read;
      begin
         Assert (Result.Success, "Separate Scheduled terminal facts are admitted");
         Assert_Equal_Int (2, Long_Long_Integer (Result.Lifecycle.Sched_Count),
                           "Scheduled declarations remain retained");
         Assert (Is_Completed
                   (Result.Lifecycle, Result.Lifecycle.Sched_Items (1).Id),
                 "Completion fact closes its declaration");
         Assert (Is_Current_Open
                   (Result.Lifecycle, Result.Lifecycle.Sched_Items (2).Id),
                 "Unterminated declaration remains open");
      end;

      Write_Facts
        ("SCHED s1 2026-10-01 cash:-100 rent:100" & ASCII.LF &
         "COMPLETE s1 e1" & ASCII.LF &
         "RETIRE s1" & ASCII.LF);
      Assert (not Read.Success, "Multiple terminal facts for one declaration reject");

      Write_Facts
        ("SCHED s1 2026-10-01 cash:-100 rent:100" & ASCII.LF &
         "SCHED s2 2026-11-01 cash:-100 rent:100" & ASCII.LF &
         "REPLACE s1 s2" & ASCII.LF &
         "REPLACE s2 s1" & ASCII.LF);
      Assert (not Read.Success, "Cyclic Scheduled replacement history rejects");

      Write_Facts
        ("SCHED s1 2026-10-01 cash:-100 rent:100" & ASCII.LF &
         "RETIRE absent" & ASCII.LF);
      Assert (not Read.Success, "Terminal reference to unknown declaration rejects");

      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Run;
end Test_Scheduled_Facts;
