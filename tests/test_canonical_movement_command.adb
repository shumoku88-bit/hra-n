with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Application.Movement_Command;
use HRA_N.Application.Movement_Command;
with HRA_N.Application.Canonical_Authority;
use HRA_N.Application.Canonical_Authority;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with Test_Support; use Test_Support;

package body Test_Canonical_Movement_Command is

   package US renames Ada.Strings.Unbounded;

   Root   : constant String := "/tmp/hra_n_canonical_movement_command";
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
         "canonical movement fixture publishes atomically");
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
     (To_Name : String;
      Amount  : Quanta_Type := 125) return Movement_Intent
   is
   begin
      return
        (From_Locus  => (Token => Make_Token ("cash")),
         To_Locus    => (Token => Make_Token (To_Name)),
         Measure     => (Token => Make_Token ("jpy")),
         Amount      => Amount,
         Valid_On    => (Year => 2026, Month => 9, Day => 22),
         Description => Make_Token ("canonical route"));
   end Intent;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Assert
        (Probe (Root).State = Legacy_Only,
         "empty root does not claim canonical authority");

      Write_Atomically
        (Actual, "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL);
      Assert
        (Probe (Root).State = Canonical_Present,
         "partial canonical authority marker selects canonical route");

      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);

      declare
         First : constant Canonical_Record_Result :=
           Record_Loam_Actual (Root, Intent ("food"));
      begin
         Assert
           (First.State = Canonical_Published_Readback_Verified,
            "canonical Application entrance publishes and verifies read-back");
         Assert
           (Equal_Token (First.Event_Id, Make_Token ("record-1")),
            "canonical Application entrance exposes writer identity");
      end;

      declare
         Image : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
      begin
         Assert (Image.Success, "canonical Application result re-admits");
         Assert_Equal_Int
           (1, Long_Long_Integer (Image.Events.Length),
            "canonical Application entrance adds exactly one Event");
      end;

      declare
         Second : constant Canonical_Record_Result :=
           Record_Loam_Actual (Root, Intent ("food", 75));
      begin
         Assert
           (Second.State = Canonical_Published_Readback_Verified,
            "second canonical Application publication verifies");
         Assert
           (Equal_Token (Second.Event_Id, Make_Token ("record-2")),
            "canonical identity allocation continues under Application routing");
      end;

      declare
         Before   : constant String := Read_Exact (Actual);
         Rejected : constant Canonical_Record_Result :=
           Record_Loam_Actual (Root, Intent ("unapproved"));
      begin
         Assert
           (Rejected.State = Canonical_Not_Published,
            "unapproved Locus is reported as not published");
         Assert
           (Read_Exact (Actual) = Before,
            "rejected canonical Application command leaves authority untouched");
      end;

      Ada.Directories.Delete_File (Policy);
      declare
         Before   : constant String := Read_Exact (Actual);
         Rejected : constant Canonical_Record_Result :=
           Record_Loam_Actual (Root, Intent ("food"));
      begin
         Assert
           (Probe (Root).State = Canonical_Present,
            "remaining actual.loam prevents transitional fallback");
         Assert
           (Rejected.State = Canonical_Not_Published,
            "partial canonical authority fails closed");
         Assert
           (Read_Exact (Actual) = Before,
            "partial canonical authority cannot mutate Actual");
      end;

      Ada.Directories.Delete_Tree (Root);
   end Run;

end Test_Canonical_Movement_Command;
