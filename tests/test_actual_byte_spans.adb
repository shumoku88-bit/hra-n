with Ada.Containers;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNAT.OS_Lib;
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
with HRA_N.Storage.Loam_Actual_Replay_Refinement;
with HRA_N.Storage.Loam_Actual_Replay_Snapshot;
with Test_Support; use Test_Support;

package body Test_Actual_Byte_Spans is

   package Bound_Replay renames
     HRA_N.Storage.Loam_Actual_Replay_Snapshot;
   package Replay_Proof renames
     HRA_N.Storage.Loam_Actual_Replay_Refinement;

   use type Ada.Containers.Count_Type;
   use type HRA_N.Core.Event.Event;
   use type Bound_Replay.Snapshot_Open_Status;
   use type Bound_Replay.Replay_Status;
   use type Replay_Proof.Qualification_Status;

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

   function Read_Path_Through_OS (Target : String) return String is
      use type GNAT.OS_Lib.File_Descriptor;
      FD       : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Closed   : Boolean := False;
      Length   : constant Integer := Integer (Ada.Directories.Size (Target));
   begin
      FD := GNAT.OS_Lib.Open_Read (Target, GNAT.OS_Lib.Binary);
      if FD = GNAT.OS_Lib.Invalid_FD then
         return "";
      end if;

      if Length = 0 then
         GNAT.OS_Lib.Close (FD, Closed);
         return (if Closed then "" else "");
      end if;

      declare
         Data : String (1 .. Length);
         Read_Count : constant Integer :=
           GNAT.OS_Lib.Read (FD, Data'Address, Data'Length);
      begin
         GNAT.OS_Lib.Close (FD, Closed);
         if not Closed or else Read_Count /= Data'Length then
            return "";
         end if;
         return Data;
      end;
   exception
      when others =>
         if FD /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (FD, Closed);
         end if;
         return "";
   end Read_Path_Through_OS;

   function Nine_Event_Document return String is
      Result : Unbounded_String :=
        To_Unbounded_String (Header & ASCII.LF);
   begin
      for I in 1 .. 9 loop
         declare
            Digit : constant Character :=
              Character'Val (Character'Pos ('0') + I);
            Key : constant String := "q" & Digit;
         begin
            Append
              (Result,
               "TX" & ASCII.HT & Key & ASCII.HT & "2026-09-25" &
               ASCII.HT & "NODESC" & ASCII.LF &
               "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" &
               ASCII.HT & "-1" & ASCII.LF &
               "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" &
               ASCII.HT & "1" & ASCII.LF &
               "ENDTX" & ASCII.LF);
         end;
      end loop;
      return To_String (Result);
   end Nine_Event_Document;

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
            Reopened    : constant String := Read_Path_Through_OS (Path);
         begin
            Assert
              (Same_Handle.Success
               and then To_String (Same_Handle.Content) = Document,
               "open handle still reads the original canonical snapshot");
            Assert
              (Reopened = Replacement_Document,
               "fresh OS open of pathname observes the replacement snapshot");
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

      --  Bind the open object and all locators into one limited capability.
      --  Callers ask by Event identity and never receive a raw span that could
      --  later be paired with a handle from a different generation.
      Write_Text (Path, Document);
      declare
         Bound         : Bound_Replay.Replay_Snapshot;
         Open_Status   : Bound_Replay.Snapshot_Open_Status;
         Reopen_Status : Bound_Replay.Snapshot_Open_Status;
      begin
         Bound_Replay.Open (Bound, Path, Open_Status);
         Assert
           (Open_Status = Bound_Replay.Snapshot_Opened,
            "snapshot-bound replay opens original generation");
         Assert
           (Bound_Replay.Is_Open (Bound),
            "snapshot-bound replay owns one open filesystem object");
         Assert
           (Bound_Replay.Event_Count (Bound) = 3,
            "snapshot-bound replay keeps all located Events");

         Bound_Replay.Open (Bound, Path, Reopen_Status);
         Assert
           (Reopen_Status = Bound_Replay.Snapshot_Already_Open,
            "open replay snapshot cannot silently rebind its pathname");

         declare
            Err      : String (1 .. 256) := [others => ' '];
            Err_Len  : Natural := 0;
            Replaced : Boolean;
         begin
            Replaced :=
              Write_File_Atomically
                (Path, Replacement_Document, Err, Err_Len);
            Assert
              (Replaced,
               "replacement generation publishes while replay snapshot is open");
         end;

         --  Map the still-open original generation into the bounded pure SPARK
         --  model only after each active Event has been replayed and compared
         --  with the semantic Event admitted from the same exact byte image.
         declare
            Qualified : constant Replay_Proof.Qualification_Result :=
              Replay_Proof.To_Bounded_Replay_Qualification
                (Bound, Snapshot);
            Replacement_Key : constant Event_Id :=
              (Token => Make_Token ("e9"));
         begin
            Assert
              (Qualified.Status = Replay_Proof.Replay_Qualified,
               "snapshot-bound production replay qualifies against bounded model");
            Assert
              (Qualified.Source.Count = 3
               and then Qualified.Replay.Count = 3
               and then Qualified.Index.Count = 3,
               "bounded replay qualification preserves complete active count");
            Assert
              (Qualified.Source.Snapshot = Snapshot
               and then Qualified.Replay.Snapshot = Snapshot
               and then Qualified.Index.Snapshot = Snapshot,
               "bounded replay qualification preserves caller proof snapshot");
            Assert
              (Replay_Index_Is_Qualified
                 (Qualified.Source, Qualified.Replay, Qualified.Index),
               "production replay bridge satisfies SPARK qualification relation");

            for I in Event_Position range 1 .. 3 loop
               declare
                  Key : constant Event_Id :=
                    HRA_N.Core.Event.Id (Qualified.Source.Events (I));
               begin
                  Assert
                    (Replay_Lookup
                       (Qualified.Source,
                        Qualified.Replay,
                        Qualified.Index,
                        Key)
                     = Reference_Lookup (Qualified.Source, Key),
                     "qualified production replay has reference lookup meaning");
               end;
            end loop;

            Assert
              (Replay_Lookup
                 (Qualified.Source,
                  Qualified.Replay,
                  Qualified.Index,
                  Replacement_Key)
               = Reference_Lookup (Qualified.Source, Replacement_Key),
               "replacement-only identity remains absent in old qualified snapshot");
         end;

         for I in Event_Position range 1 .. 3 loop
            declare
               Key : constant Event_Id :=
                 HRA_N.Core.Event.Id (Parsed.Events.Element (I));
               Replayed : constant Bound_Replay.Replay_Result :=
                 Bound_Replay.Replay_Event (Bound, Key);
            begin
               Assert
                 (Replayed.Status = Bound_Replay.Replay_Succeeded,
                  "bound replay finds Event from original generation");
               Assert
                 (Replayed.Decoded.Success,
                  "bound replay decodes original Event block");
               Assert
                 (Replayed.Decoded.Value = Parsed.Events.Element (I),
                  "bound replay preserves complete original Event");
            end;
         end loop;

         declare
            Replacement_Key : constant Event_Id :=
              (Token => Make_Token ("e9"));
            Replayed : constant Bound_Replay.Replay_Result :=
              Bound_Replay.Replay_Event (Bound, Replacement_Key);
         begin
            Assert
              (Replayed.Status = Bound_Replay.Replay_Event_Not_Found,
               "open replay snapshot does not observe replacement-only Event");
         end;

         Bound_Replay.Close (Bound);
         Assert
           (not Bound_Replay.Is_Open (Bound),
            "bound replay snapshot closes explicitly");
         Assert
           (Bound_Replay.Event_Count (Bound) = 0,
            "closing bound replay drops active locator count");

         declare
            Closed_Qualification : constant Replay_Proof.Qualification_Result :=
              Replay_Proof.To_Bounded_Replay_Qualification
                (Bound, Snapshot);
         begin
            Assert
              (Closed_Qualification.Status =
                 Replay_Proof.Replay_Snapshot_Closed,
               "closed production snapshot cannot enter bounded replay proof");
            Assert
              (Closed_Qualification.Source.Count = 0
               and then Closed_Qualification.Replay.Count = 0
               and then Closed_Qualification.Index.Count = 0,
               "failed replay qualification exposes no accepted prefix");
         end;

         --  Explicit close/reopen is the generation transition boundary.
         Bound_Replay.Open (Bound, Path, Open_Status);
         Assert
           (Open_Status = Bound_Replay.Snapshot_Opened,
            "closed replay snapshot may bind to replacement generation");
         Assert
           (Bound_Replay.Event_Count (Bound) = 1,
            "reopened replay snapshot locates replacement generation");

         declare
            Replacement_Key : constant Event_Id :=
              (Token => Make_Token ("e9"));
            Old_Key : constant Event_Id :=
              (Token => Make_Token ("e1"));
            New_Replay : constant Bound_Replay.Replay_Result :=
              Bound_Replay.Replay_Event (Bound, Replacement_Key);
            Old_Replay : constant Bound_Replay.Replay_Result :=
              Bound_Replay.Replay_Event (Bound, Old_Key);
         begin
            Assert
              (New_Replay.Status = Bound_Replay.Replay_Succeeded,
               "reopened snapshot replays replacement Event");
            Assert
              (Old_Replay.Status = Bound_Replay.Replay_Event_Not_Found,
               "reopened snapshot no longer exposes prior generation Event");
         end;

         Bound_Replay.Close (Bound);

         --  Structural TX/ENDTX location alone is not sufficient.  A snapshot
         --  is not opened unless the exact same bytes also pass global semantic
         --  admission.
         declare
            Unsupported_Document : constant String :=
              Header & ASCII.LF &
              "TX" & ASCII.HT & "e-unsupported" & ASCII.HT &
              "2026-09-25" & ASCII.HT & "NODESC" & ASCII.LF &
              "DATE-REV" & ASCII.HT & "rev-1" & ASCII.HT &
              "2026-09-26" & ASCII.HT & "REPLACES" & ASCII.HT &
              "ROOT" & ASCII.LF &
              "ENDTX" & ASCII.LF;
            Unsupported_Status : Bound_Replay.Snapshot_Open_Status;
         begin
            Write_Text (Path, Unsupported_Document);
            Bound_Replay.Open (Bound, Path, Unsupported_Status);
            Assert
              (Unsupported_Status = Bound_Replay.Snapshot_Admission_Failed,
               "structurally locatable but semantically unsupported snapshot fails closed");
            Assert
              (not Bound_Replay.Is_Open (Bound),
               "failed semantic admission does not leave a replay handle open");
            Assert
              (Bound_Replay.Event_Count (Bound) = 0,
               "failed semantic admission exposes no replay locators");
         end;

         --  The production capability may admit more Events than the bounded
         --  proof carrier.  The bridge must reject the whole image rather than
         --  silently presenting the first eight Events as qualified.
         Write_Text (Path, Nine_Event_Document);
         Bound_Replay.Open (Bound, Path, Open_Status);
         Assert
           (Open_Status = Bound_Replay.Snapshot_Opened,
            "production replay snapshot admits nine valid Events");
         Assert
           (Bound_Replay.Event_Count (Bound) = 9,
            "production replay keeps all nine Events before proof adaptation");

         declare
            Too_Large : constant Replay_Proof.Qualification_Result :=
              Replay_Proof.To_Bounded_Replay_Qualification
                (Bound, Snapshot);
         begin
            Assert
              (Too_Large.Status =
                 Replay_Proof.Replay_Over_Bounded_Capacity,
               "bounded replay bridge rejects nine Events without truncation");
            Assert
              (Too_Large.Source.Count = 0
               and then Too_Large.Replay.Count = 0
               and then Too_Large.Index.Count = 0,
               "over-capacity replay qualification exposes no accepted prefix");
         end;
         Bound_Replay.Close (Bound);
      end;

      Cleanup;
   end Run;

end Test_Actual_Byte_Spans;
