with Ada.Directories;
with Ada.Text_IO;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with Test_Support; use Test_Support;

package body Test_Transaction_Metadata is
   procedure Run is
      Path : constant String := "/tmp/hra_n_test_transaction_metadata.hra";

      procedure Write_Journal (Content : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put (File, Content);
         Ada.Text_IO.Close (File);
      end Write_Journal;
   begin
      Write_Journal
        ("TX e1 2026-09-14 cash:-100 food:100 @food ""Lunch"" relation:r1" & ASCII.LF &
         "TX e2 2026-09-15 cash:-100 food:100 replaces:e1 discharges:r1" & ASCII.LF);
      declare
         Journal : constant Journal_Result := Read_Journal_File (Path);
         First   : Transaction_Metadata_Entry;
         Second  : Transaction_Metadata_Entry;
         Found   : Boolean;
      begin
         Assert (Journal.Success, "Complete transaction metadata journal is admitted");
         Assert_Equal_Int (2, Long_Long_Integer (Entry_Count (Journal.Metadata)),
                           "Every transaction receives one metadata row");
         Find_Metadata
           (Journal.Metadata, (Token => Make_Token ("e1")), First, Found);
         Assert (Found and then First.Purpose.Present
                 and then First.Purpose.Value.Value (1 .. First.Purpose.Value.Length) = "food",
                 "Purpose metadata survives parsing");
         Assert (First.Relation.Present
                 and then First.Relation.Value.Value (1 .. First.Relation.Value.Length) = "r1",
                 "Relation metadata survives parsing");
         Find_Metadata
           (Journal.Metadata, (Token => Make_Token ("e2")), Second, Found);
         Assert (Found and then Second.Replaces.Present
                 and then Equal_Token (Second.Replaces.Value.Token, Make_Token ("e1")),
                 "Replacement metadata survives parsing");
         Assert (Second.Discharge.Present
                 and then Second.Discharge.Value.Value
                   (1 .. Second.Discharge.Value.Length) = "r1",
                 "Discharge metadata survives parsing");
      end;

      Write_Journal
        ("TX e1 2026-09-14 cash:-100 food:100" & ASCII.LF &
         "TX e2 2026-09-15 cash:-100 food:100 replaces:missing" & ASCII.LF);
      Assert (not Read_Journal_File (Path).Success,
              "Unknown replacement target fails closed");

      Write_Journal
        ("TX e1 2026-09-14 cash:-100 food:100" & ASCII.LF &
         "TX e2 2026-09-15 cash:-100 food:100 replaces:e1" & ASCII.LF &
         "TX e3 2026-09-16 cash:-100 food:100 replaces:e1" & ASCII.LF);
      Assert (not Read_Journal_File (Path).Success,
              "Branching replacement history fails closed");

      Write_Journal
        ("TX e1 2026-09-14 cash:-100 food:100 replaces:e2" & ASCII.LF &
         "TX e2 2026-09-15 cash:-100 food:100 replaces:e1" & ASCII.LF);
      Assert (not Read_Journal_File (Path).Success,
              "Cyclic replacement history fails closed");

      Write_Journal
        ("TX e1 2026-09-14 cash:-100 food:100 @food @other" & ASCII.LF);
      Assert (not Read_Journal_File (Path).Success,
              "Duplicate metadata field fails closed");

      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Run;
end Test_Transaction_Metadata;
