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
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Actual_Byte_Spans;
use HRA_N.Storage.Loam_Actual_Byte_Spans;
with HRA_N.Storage.Loam_Actual_Event_Block;
use HRA_N.Storage.Loam_Actual_Event_Block;
with HRA_N.Storage.Loam_Actual_Reader;
use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Refinement;
use HRA_N.Storage.Loam_Actual_Refinement;
with Test_Support; use Test_Support;

package body Test_Actual_Byte_Spans is

   use type Ada.Containers.Count_Type;
   use type HRA_N.Core.Event.Event;

   Path   : constant String := "/tmp/hra_n_actual_byte_spans.loam";
   Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";

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
   end Cleanup;

   procedure Run is
      Snapshot : constant Snapshot_Id := 77;

      --  One globally admitted document containing both kinds of cross-Event
      --  reference. Each individual span must still be locally decodable
      --  without pretending that it is a complete admitted document.
      Document : constant String :=
        Header & ASCII.LF &
        "TX" & ASCII.HT & "e1" & ASCII.HT & "2026-09-21" & ASCII.HT &
        "DESC" & ASCII.HT & "root event" & ASCII.LF &
        "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
        "-100" & ASCII.LF &
        "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
        "100" & ASCII.LF &
        "ENDTX" & ASCII.LF &
        "TX" & ASCII.HT & "e2" & ASCII.HT & "2026-09-22" & ASCII.HT &
        "DESC" & ASCII.HT & "corrected event" & ASCII.LF &
        "REPLACES" & ASCII.HT & "e1" & ASCII.LF &
        "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
        "-120" & ASCII.LF &
        "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
        "120" & ASCII.LF &
        "ENDTX" & ASCII.LF &
        "TX" & ASCII.HT & "e3" & ASCII.HT & "2026-09-23" & ASCII.HT &
        "NODESC" & ASCII.LF &
        "REVERSAL-OF" & ASCII.HT & "e2" & ASCII.LF &
        "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
        "120" & ASCII.LF &
        "KEYED-EFFECT" & ASCII.HT & "right" & ASCII.HT & "food" &
        ASCII.HT & "jpy" & ASCII.HT & "-120" & ASCII.LF &
        "ENDTX" & ASCII.LF;

      Replacement_Document : constant String :=
        Header & ASCII.LF &
        "TX" & ASCII.HT & "e9" & ASCII.HT & "2026-09-24" & ASCII.HT &
        "NODESC" & ASCII.LF &
        "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT &
        "-1" & ASCII.LF &
        "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT &
        "1" & ASCII.LF &
        "ENDTX" & ASCII.LF;

      Parsed : Loam_Actual_Result;
      Exact  : HRA_N.Storage.Exact_File.Read_Result;
      Handle : HRA_N.Storage.Exact_File.Snapshot_Handle;
      Opened : Boolean;
   begin
      Cleanup;
      Write_Text (Path, Document);

      Parsed := Read_Loam_Actual_File (Path);
      Assert
        (Parsed.Success,
         "production reader admits complete correction/reversal fixture");
      Assert
        (Parsed.Events.Length = 3,
         "relational fixture contains three production Events");

      HRA_N.Storage.Exact_File.Open_Snapshot (Handle, Path, Opened);
      Assert (Opened, "canonical Actual snapshot opens once");
      Assert
        (HRA_N.Storage.Exact_File.Snapshot_Is_Open (Handle),
         "open snapshot handle remains live");

      Exact := HRA_N.Storage.Exact_File.Read_All (Handle);
      Assert (Exact.Success, "exact canonical bytes are readable from one handle");
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
         Assert
           (Adapted.Status = Refined,
            "production relational fixture refines to bounded image");

         --  Rebind the pathname using HRA-N's normal atomic publication path.
         --  The already-open handle must continue to identify the original
         --  file object while a fresh path open observes the replacement.
         declare
            Err       : String (1 .. 256) := [others => ' '];
            Err_Len   : Natural := 0;
            Replaced  : Boolean;
         begin
            Replaced :=
              Write_File_Atomically
                (Path, Replacement_Document, Err, Err_Len);
            Assert
              (Replaced,
               "HRA-N atomic writer replaces pathname while snapshot is open");
         end;

         declare
            Same_Handle : constant HRA_N.Storage.Exact_File.Read_Result :=
              HRA_N.Storage.Exact_File.Read_All (Handle);
            Reopened    : constant HRA_N.Storage.Exact_File.Read_Result :=
              HRA_N.Storage.Exact_File.Read_All (Path);
         begin
            Assert
              (Same_Handle.Success
               and then To_String (Same_Handle.Content) = Document,
               "open handle still reads the original canonical snapshot");
            Assert
              (Reopened.Success
               and then To_String (Reopened.Content) = Replacement_Document,
               "reopening the pathname observes the replacement snapshot");
         end;

         for I in Event_Position range 1 .. 3 loop
            declare
               Span      : constant Event_Byte_Span := Located.Spans (I);
               Range_Read : constant HRA_N.Storage.Exact_File.Read_Result :=
                 HRA_N.Storage.Exact_File.Read_Range
                   (Handle,
                    Positive (Span.First_Byte),
                    Positive (Span.Last_Byte));
               Block     : constant String := To_String (Range_Read.Content);
               Decoded   : constant Event_Block_Result :=
                 Decode_Event_Block (Block);
            begin
               Assert
                 (Span_Is_Valid (Bytes, Span),
                  "located Event span is inside exact snapshot");
               Assert
                 (Range_Read.Success,
                  "exact byte range is readable without materializing whole file");
               Assert
                 (Block = Slice_Event_Block (Bytes, Span),
                  "seek-based byte range equals the locator slice");
               Assert
                 (Equal_Token
                    (Span.Key.Token,
                     HRA_N.Core.Event.Id (Parsed.Events.Element (I)).Token),
                  "byte-span key matches production Event identity");

               Assert
                 (Decoded.Success,
                  "isolated Event span decodes without document admission");
               Assert
                 (Decoded.Value = Parsed.Events.Element (I),
                  "local span decode preserves complete production Event");
               Assert
                 (Equal_Token
                    (Decoded.Validity.Event_Id.Token, Span.Key.Token),
                  "local decoder preserves Event validity identity");

               if I = 1 then
                  Assert
                    (Decoded.Has_Description,
                     "root span retains local description evidence");
                  Assert
                    (not Decoded.Metadata.Replaces.Present
                     and then not Decoded.Metadata.Reverses.Present,
                     "root span has no cross-Event metadata");
               elsif I = 2 then
                  Assert
                    (Decoded.Has_Description,
                     "correction span retains local description evidence");
                  Assert
                    (Decoded.Metadata.Replaces.Present
                     and then Equal_Token
                       (Decoded.Metadata.Replaces.Value.Token,
                        Make_Token ("e1")),
                     "correction span retains REPLACES without target co-location");
               else
                  Assert
                    (not Decoded.Has_Description,
                     "reversal span retains NODESC meaning");
                  Assert
                    (Decoded.Metadata.Reverses.Present
                     and then Equal_Token
                       (Decoded.Metadata.Reverses.Value.Token,
                        Make_Token ("e2")),
                     "reversal span retains REVERSAL-OF without target co-location");
               end if;

               Replay.Slots (I) := Decoded.Value;
               Index.Bindings (I) :=
                 (Key     => Span.Key,
                  Locator => I);
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

      Assert
        (HRA_N.Storage.Exact_File.Snapshot_Is_Open (Handle),
         "range replay keeps the original snapshot handle open");
      HRA_N.Storage.Exact_File.Close_Snapshot (Handle);
      Assert
        (not HRA_N.Storage.Exact_File.Snapshot_Is_Open (Handle),
         "snapshot handle closes explicitly");

      Cleanup;
   end Run;

end Test_Actual_Byte_Spans;
