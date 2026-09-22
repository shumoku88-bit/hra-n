with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Application.Movement_Command;
use HRA_N.Application.Movement_Command;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with Test_Support; use Test_Support;

package body Test_Canonical_Correction_Command is

   package US renames Ada.Strings.Unbounded;

   Root   : constant String := "/tmp/hra_n_canonical_correction_command";
   Actual : constant String := Root & "/actual.loam";
   Policy : constant String := Root & "/locus-admission.loam";
   HT     : constant String := [1 => ASCII.HT];
   NL     : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "canonical correction fixture publishes atomically");
   end Write_Atomically;

   function Read_Exact (Path : String) return String is
      Item : constant HRA_N.Storage.Exact_File.Read_Result :=
        HRA_N.Storage.Exact_File.Read_All (Path);
   begin
      if not Item.Success then
         return "";
      end if;
      return US.To_String (Item.Content);
   end Read_Exact;

   function Intent
     (Target : String;
      Amount : Quanta_Type;
      Date   : Date_Type := (Year => 2026, Month => 9, Day => 20);
      Desc   : String := "corrected route") return Correction_Intent
   is
   begin
      return
        (Target_Id   => Make_Token (Target),
         From_Locus  => (Token => Make_Token ("cash")),
         To_Locus    => (Token => Make_Token ("food")),
         Measure     => (Token => Make_Token ("jpy")),
         Amount      => Amount,
         Valid_On    => Date,
         Description => Make_Token (Desc));
   end Intent;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "record-1" & HT & "2026-09-20"
         & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-10" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "10" & NL
         & "ENDTX" & NL);
      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);

      declare
         First : constant Canonical_Correction_Result :=
           Correct_Loam_Actual
             (Root, Intent ("record-1", 15), False);
      begin
         Assert
           (First.State = Canonical_Published_Readback_Verified,
            "canonical correction publishes and snapshot-verifies");
         Assert
           (Equal_Token (First.Event_Id, Make_Token ("replacement-1")),
            "canonical correction exposes fresh replacement identity");
         Assert
           (First.Has_Effective_Date
            and then Equal_Date
              (First.Effective_Date,
               (Year => 2026, Month => 9, Day => 20)),
            "canonical correction reports inherited target date");
      end;

      declare
         Image : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
         Successor : Event_Id;
         Found : Boolean;
      begin
         Assert (Image.Success, "canonical correction result re-admits");
         Find_Successor
           (Image.Metadata,
            (Token => Make_Token ("record-1")),
            Successor,
            Found);
         Assert
           (Found
            and then Equal_Token
              (Successor.Token, Make_Token ("replacement-1")),
            "canonical Application route retains explicit REPLACES topology");
      end;

      declare
         Before : constant String := Read_Exact (Actual);
         Mismatch : constant Canonical_Correction_Result :=
           Correct_Loam_Actual
             (Root,
              Intent
                ("replacement-1",
                 20,
                 (Year => 2026, Month => 9, Day => 22),
                 "wrong date"),
              True);
      begin
         Assert
           (Mismatch.State = Canonical_Not_Published,
            "explicit different date is not silently ignored");
         Assert
           (Index
              (Mismatch.Diagnostic (1 .. Mismatch.Diagnostic_Len),
               "inherits the target occurrence date") > 0,
            "date mismatch explains canonical inheritance rule");
         Assert
           (Read_Exact (Actual) = Before,
            "date mismatch leaves canonical authority untouched");
      end;

      declare
         Second : constant Canonical_Correction_Result :=
           Correct_Loam_Actual
             (Root,
              Intent ("replacement-1", 20),
              True);
      begin
         Assert
           (Second.State = Canonical_Published_Readback_Verified,
            "explicit matching date remains admissible");
         Assert
           (Equal_Token
              (Second.Event_Id, Make_Token ("replacement-2")),
            "canonical correction chain continues through Application route");
      end;

      declare
         Before : constant String := Read_Exact (Actual);
         Old_Target : constant Canonical_Correction_Result :=
           Correct_Loam_Actual
             (Root, Intent ("record-1", 25), False);
      begin
         Assert
           (Old_Target.State = Canonical_Not_Published,
            "superseded target is rejected before publication");
         Assert
           (Read_Exact (Actual) = Before,
            "superseded target rejection leaves authority untouched");
      end;

      Ada.Directories.Delete_File (Policy);
      declare
         Before : constant String := Read_Exact (Actual);
         Partial : constant Canonical_Correction_Result :=
           Correct_Loam_Actual
             (Root, Intent ("replacement-2", 25), False);
      begin
         Assert
           (Canonical_Authority_Present (Root),
            "partial canonical authority still selects canonical route");
         Assert
           (Partial.State = Canonical_Not_Published,
            "missing canonical policy fails closed");
         Assert
           (Read_Exact (Actual) = Before,
            "partial canonical authority cannot mutate Actual");
      end;

      Ada.Directories.Delete_Tree (Root);
   end Run;

end Test_Canonical_Correction_Command;
