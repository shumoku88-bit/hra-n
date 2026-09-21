with Ada.Directories;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO;
with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Reader_Refinement;
use HRA_N.Core.Actual_Reader_Refinement;
with HRA_N.Core.Event;
with HRA_N.Storage.Loam_Actual_Reader;
use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Refinement;
use HRA_N.Storage.Loam_Actual_Refinement;
with Test_Support; use Test_Support;

package body Test_Actual_Reader_Refinement is

   use type HRA_N.Core.Event.Event;
   use type HRA_N.Core.Event.Effect_List;

   Path : constant String := "/tmp/hra_n_actual_refinement.loam";

   procedure Write_Canonical (Count : Natural) is
      File : Ada.Text_IO.File_Type;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line
        (File, "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1");
      for I in 1 .. Count loop
         declare
            N : constant String := Trim (Positive'Image (I), Both);
         begin
            Ada.Text_IO.Put_Line
              (File,
               "TX" & ASCII.HT & "ref-" & N & ASCII.HT & "2026-09-21" &
               ASCII.HT & "NODESC");
            Ada.Text_IO.Put_Line
              (File,
               "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" &
               ASCII.HT & "-" & N);
            Ada.Text_IO.Put_Line
              (File,
               "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" &
               ASCII.HT & N);
            Ada.Text_IO.Put_Line (File, "ENDTX");
         end;
      end loop;
      Ada.Text_IO.Close (File);
   end Write_Canonical;

   procedure Run is
      Snapshot : constant Snapshot_Id := 42;
   begin
      Write_Canonical (0);
      declare
         Parsed  : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
         Adapted : constant Adapter_Result :=
           To_Bounded_Semantic_Image (Parsed, Snapshot);
      begin
         Assert (Parsed.Success, "production reader accepts empty canonical Actual");
         Assert (Adapted.Status = Refined, "empty reader result refines");
         Assert (Adapted.Image.Count = 0, "empty refinement preserves count");
         Assert
           (Adapted.Image.Snapshot = Snapshot,
            "empty refinement preserves caller snapshot token");
      end;

      Write_Canonical (3);
      declare
         Parsed  : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
         Adapted : constant Adapter_Result :=
           To_Bounded_Semantic_Image (Parsed, Snapshot);
      begin
         Assert (Parsed.Success, "production reader accepts small canonical Actual");
         Assert (Adapted.Status = Refined, "small reader result refines");
         Assert (Adapted.Image.Count = 3, "refinement preserves production count");
         Assert
           (Adapted.Image.Snapshot = Snapshot,
            "refinement uses caller-supplied snapshot unchanged");
         Assert
           (Reader_Result_Refines (Parsed, Snapshot, Adapted.Image),
            "adapter relation holds for production reader result");

         for I in Event_Position range 1 .. 3 loop
            declare
               Parsed_Event : constant HRA_N.Core.Event.Event :=
                 Parsed.Events.Element (I);
            begin
               Assert
                 (Adapted.Image.Events (I) = Parsed_Event,
                  "source position and complete Event are preserved");
               Assert
                 (Same_Id
                    (HRA_N.Core.Event.Id (Adapted.Image.Events (I)),
                     HRA_N.Core.Event.Id (Parsed_Event)),
                  "EventId is preserved");
               Assert
                 (HRA_N.Core.Event.Effects (Adapted.Image.Events (I)) =
                    HRA_N.Core.Event.Effects (Parsed_Event),
                  "Effects payload is preserved");
            end;
         end loop;
      end;

      Write_Canonical (9);
      declare
         Parsed  : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
         Adapted : constant Adapter_Result :=
           To_Bounded_Semantic_Image (Parsed, Snapshot);
      begin
         Assert (Parsed.Success, "production reader accepts nine Events");
         Assert
           (Adapted.Status = Too_Many_Events,
            "over-eight production image is rejected without truncation");
         Assert
           (Adapted.Image.Count = 0,
            "over-capacity input does not expose an accepted prefix");
      end;

      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      declare
         Parsed  : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
         Adapted : constant Adapter_Result :=
           To_Bounded_Semantic_Image (Parsed, Snapshot);
      begin
         Assert (not Parsed.Success, "production reader reports missing file failure");
         Assert
           (Adapted.Status = Reader_Failed,
            "failed production result cannot refine");
      end;

      Write_Canonical (1);
      declare
         Parsed : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
         Duplicate : Loam_Actual_Result;
         Adapted   : Adapter_Result;
      begin
         Duplicate.Success := True;
         Duplicate.Events.Append (Parsed.Events.Element (1));
         Duplicate.Events.Append (Parsed.Events.Element (1));
         Adapted := To_Bounded_Semantic_Image (Duplicate, Snapshot);
         Assert
           (Adapted.Status =
              HRA_N.Core.Actual_Reader_Refinement.Duplicate_Event_Id,
            "duplicate production identity is explicitly rejected");
      end;

      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Run;

end Test_Actual_Reader_Refinement;
