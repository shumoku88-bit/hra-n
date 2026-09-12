with Ada.Directories;
with Ada.Text_IO;
with HRA_N.Core.Event;                       use HRA_N.Core.Event;
with HRA_N.Core.Types;                       use HRA_N.Core.Types;
with HRA_N.Core.Validity;                    use HRA_N.Core.Validity;
with HRA_N.Storage.Journal_Reader;           use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader;            use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Storage.Scheduled_Journal_Writer;
with Test_Support;                           use Test_Support;

package body Test_HRA_Storage_Portable is

   procedure Run is
      Tmp_Journal : constant String := "/tmp/hra_n_storage_portable_journal.hra";
      Tmp_Policy  : constant String := "/tmp/hra_n_storage_portable_policy.hra";
      Src_Sched   : constant String := "/tmp/hra_n_storage_portable_source_scheduled.hra";
      Dst_Sched   : constant String := "/tmp/hra_n_storage_portable_written_scheduled.hra";

      procedure Remove_If_Present (Path : String) is
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
      end Remove_If_Present;

      procedure Write_Text (Path : String; Content : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put (File, Content);
         Ada.Text_IO.Close (File);
      end Write_Text;
   begin
      Assert
        (not Read_Journal_File ("/non/existent/hra_n_portable_journal.hra").Success,
         "Non-existent journal fails closed");
      Assert
        (not Read_Policy_File ("/non/existent/hra_n_portable_policy.hra").Success,
         "Non-existent policy fails closed");
      Assert
        (not Read_Scheduled_Journal_File
           ("/non/existent/hra_n_portable_scheduled.hra").Success,
         "Non-existent scheduled journal fails closed");

      Remove_If_Present (Tmp_Journal);
      declare
         Effects : Effect_List;
         Written : HRA_N.Storage.Journal_Writer.Append_Result;
      begin
         Effects.Count := 2;
         Effects.Values (1) :=
           (Key     => (Token => Make_Token ("f1")),
            Locus   => (Token => Make_Token ("cash")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => -100));
         Effects.Values (2) :=
           (Key     => (Token => Make_Token ("f2")),
            Locus   => (Token => Make_Token ("food")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => 100));

         Written := HRA_N.Storage.Journal_Writer.Append_Transaction
           (Journal_Path => Tmp_Journal,
            Tx_Id        => "e0001",
            Valid_On     => Make_Date (2026, 9, 10),
            Effects      => Effects,
            Purpose      => "food",
            Description  => "Portable storage roundtrip");
         Assert (Written.Success, "Journal writer accepts portable fixture");

         declare
            Read_Back : constant Journal_Result := Read_Journal_File (Tmp_Journal);
         begin
            Assert (Read_Back.Success, "Journal reader admits writer output");
            Assert_Equal_Int
              (1, Long_Long_Integer (Read_Back.Events.Length),
               "Journal roundtrip preserves one event");
         end;
      end;

      Write_Text
        (Tmp_Policy,
         "LOCUS cash" & ASCII.LF
         & "LOCUS food" & ASCII.LF
         & "CAPACITY food 5000 jpy" & ASCII.LF
         & "EFFECTIVE cap0001 2026-09-01" & ASCII.LF);
      declare
         Policy : constant Policy_Result := Read_Policy_File (Tmp_Policy);
      begin
         Assert (Policy.Success, "Policy reader admits portable fixture");
         Assert_Equal_Int
           (1, Long_Long_Integer (Policy.Capacities.Movement_Count),
            "Policy fixture retains one capacity movement");
      end;

      Write_Text
        (Src_Sched,
         "SCHED s1 2026-10-01 cash:-100 rent:100" & ASCII.LF
         & "SCHED s2 2026-11-01 cash:-100 rent:100" & ASCII.LF
         & "COMPLETE s1 e1" & ASCII.LF);
      declare
         Source : constant Scheduled_Journal_Result :=
           Read_Scheduled_Journal_File (Src_Sched);
         Written : HRA_N.Storage.Scheduled_Journal_Writer.Write_Result;
      begin
         Assert (Source.Success, "Scheduled reader admits portable fixture");
         Written :=
           HRA_N.Storage.Scheduled_Journal_Writer.Write_Scheduled_Journal_File
             (Path      => Dst_Sched,
              Lifecycle => Source.Lifecycle);
         Assert (Written.Success, "Scheduled writer emits portable fixture");

         declare
            Read_Back : constant Scheduled_Journal_Result :=
              Read_Scheduled_Journal_File (Dst_Sched);
         begin
            Assert (Read_Back.Success, "Scheduled reader admits writer output");
            Assert_Equal_Int
              (2, Long_Long_Integer (Read_Back.Lifecycle.Sched_Count),
               "Scheduled roundtrip preserves two declarations");
            Assert_Equal_Int
              (1, Long_Long_Integer (Read_Back.Lifecycle.Comp_Count),
               "Scheduled roundtrip preserves one completion");
         end;
      end;

      Remove_If_Present (Tmp_Journal);
      Remove_If_Present (Tmp_Policy);
      Remove_If_Present (Src_Sched);
      Remove_If_Present (Dst_Sched);
   end Run;

end Test_HRA_Storage_Portable;
