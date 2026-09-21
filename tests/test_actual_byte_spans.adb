with Ada.Containers;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Replay_Refinement;
use HRA_N.Core.Actual_Replay_Refinement;
with HRA_N.Core.Actual_Reader_Refinement;
use HRA_N.Core.Actual_Reader_Refinement;
with HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Byte_Spans;
use HRA_N.Storage.Loam_Actual_Byte_Spans;
with HRA_N.Storage.Loam_Actual_Reader;
use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Refinement;
use HRA_N.Storage.Loam_Actual_Refinement;
with Test_Support; use Test_Support;

package body Test_Actual_Byte_Spans is

   use type Ada.Containers.Count_Type;
   use type HRA_N.Core.Event.Event;

   Path        : constant String := "/tmp/hra_n_actual_byte_spans.loam";
   Replay_Path : constant String := "/tmp/hra_n_actual_byte_replay.loam";
   Header      : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";

   procedure Write_Text (Target : String; Text : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      if Ada.Directories.Exists (Target) then
         Ada.Directories.Delete_File (Target);
      end if;

      SIO.Create (File, SIO.Out_File, Target);
      if Text'Length > 0 then
         declare
            Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
            J : Ada.Streams.Stream_Element_Offset := Data'First;
         begin
            for I in Text'Range loop
               Data (J) := Ada.Streams.Stream_Element (Character'Pos (Text (I)));
               J := Ada.Streams.Stream_Element_Offset'Succ (J);
            end loop;
            SIO.Write (File, Data);
         end;
      end if;
      SIO.Close (File);
   end Write_Text;

   procedure Cleanup is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      if Ada.Directories.Exists (Replay_Path) then
         Ada.Directories.Delete_File (Replay_Path);
      end if;
   end Cleanup;

   procedure Run is
      Snapshot : constant Snapshot_Id := 77;
      Document : constant String :=
        Header & ASCII.LF &
        "TX" & ASCII.HT & "e1" & ASCII.HT & "2026-09-21" & ASCII.HT &
        "NODESC" & ASCII.LF &
        "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
        "-10" & ASCII.LF &
        "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
        "10" & ASCII.LF &
        "ENDTX" & ASCII.LF &
        "TX" & ASCII.HT & "e2" & ASCII.HT & "2026-09-22" & ASCII.HT &
        "DESC" & ASCII.HT & "second event" & ASCII.LF &
        "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
        "-20" & ASCII.LF &
        "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
        "20" & ASCII.LF &
        "ENDTX" & ASCII.LF &
        "TX" & ASCII.HT & "e3" & ASCII.HT & "2026-09-23" & ASCII.HT &
        "NODESC" & ASCII.LF &
        "KEYED-EFFECT" & ASCII.HT & "left" & ASCII.HT & "cash" &
        ASCII.HT & "jpy" & ASCII.HT & "-30" & ASCII.LF &
        "KEYED-EFFECT" & ASCII.HT & "right" & ASCII.HT & "food" &
        ASCII.HT & "jpy" & ASCII.HT & "30" & ASCII.LF &
        "ENDTX" & ASCII.LF;

      Parsed  : Loam_Actual_Result;
      Exact   : HRA_N.Storage.Exact_File.Read_Result;
   begin
      Cleanup;
      Write_Text (Path, Document);

      Parsed := Read_Loam_Actual_File (Path);
      Assert (Parsed.Success, "production reader accepts byte-span fixture");
      Assert (Parsed.Events.Length = 3, "fixture contains three production Events");

      Exact := HRA_N.Storage.Exact_File.Read_All (Path);
      Assert (Exact.Success, "exact canonical bytes are readable");
      Assert
        (To_String (Exact.Content) = Document,
         "fixture writer preserves exact canonical bytes");

      declare
         Bytes   : constant String := To_String (Exact.Content);
         Located : constant Locate_Result := Locate_Event_Byte_Spans (Bytes);
         Adapted : constant Adapter_Result :=
           To_Bounded_Semantic_Image (Parsed, Snapshot);
         Replay  : Replay_View :=
           (Snapshot => Snapshot,
            Count    => 3,
            Slots    => Adapted.Image.Events);
         Index   : Replay_Index :=
           (Snapshot => Snapshot,
            Count    => 3,
            Bindings => [others => <>]);
      begin
         Assert (Located.Success, "byte-span locator accepts canonical bytes");
         Assert (Located.Count = 3, "byte-span locator finds every Event");
         Assert (Adapted.Status = Refined, "production fixture refines to bounded image");

         for I in Event_Position range 1 .. 3 loop
            declare
               Span  : constant Event_Byte_Span := Located.Spans (I);
               Block : constant String := Slice_Event_Block (Bytes, Span);
               Replayed : Loam_Actual_Result;
            begin
               Assert
                 (Span_Is_Valid (Bytes, Span),
                  "located Event span is inside exact snapshot");
               Assert
                 (Equal_Token
                    (Span.Key.Token,
                     HRA_N.Core.Event.Id
                       (Parsed.Events.Element (Positive (I))).Token),
                  "byte-span key matches production Event identity");

               Write_Text
                 (Replay_Path,
                  Header & ASCII.LF & Block);
               Replayed := Read_Loam_Actual_File (Replay_Path);

               Assert
                 (Replayed.Success,
                  "isolated byte span replays through production reader");
               Assert
                 (Replayed.Events.Length = 1,
                  "isolated byte span decodes exactly one Event");
               Assert
                 (Replayed.Events.Element (1) =
                    Parsed.Events.Element (Positive (I)),
                  "byte-span replay preserves complete production Event");

               Replay.Slots (I) := Replayed.Events.Element (1);
               Index.Bindings (I) :=
                 (Key     => Span.Key,
                  Locator => Replay_Locator (I));
            end;
         end loop;

         Assert
           (Replay_Index_Is_Qualified (Adapted.Image, Replay, Index),
            "production byte spans satisfy bounded replay qualification");

         for I in Event_Position range 1 .. 3 loop
            declare
               Key : constant Event_Id :=
                 HRA_N.Core.Event.Id (Adapted.Image.Events (I));
            begin
               Assert
                 (Replay_Lookup (Adapted.Image, Replay, Index, Key) =
                    Reference_Lookup (Adapted.Image, Key),
                  "production byte-span replay has reference lookup meaning");
            end;
         end loop;
      end;

      Cleanup;
   end Run;

end Test_Actual_Byte_Spans;
