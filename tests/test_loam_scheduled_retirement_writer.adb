with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with HRA_N.Storage.Loam_Scheduled_Retirement_Writer;
use HRA_N.Storage.Loam_Scheduled_Retirement_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Retirement_Writer is

   package US renames Ada.Strings.Unbounded;

   Root      : constant String := "/tmp/hra_n_loam_scheduled_retirement_writer";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "retirement writer fixture publishes atomically");
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

   procedure Reset_Root is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
   end Reset_Root;

   function Lifecycle
     (Completion_Line : String := "";
      Retirement_Line : String := "";
      Replacement_Line : String := "") return String
   is
   begin
      return
        "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
        & "BEGIN" & HT & "Scheduled" & NL
        & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
        & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-23" & HT & "jpy" & NL
        & "CHANGE" & HT & "cash" & HT & "-75" & NL
        & "CHANGE" & HT & "food" & HT & "75" & NL
        & "SCHEDULED" & HT & "scheduled-2" & HT & "2026-09-24" & HT & "jpy" & NL
        & "CHANGE" & HT & "cash" & HT & "-20" & NL
        & "CHANGE" & HT & "food" & HT & "20" & NL
        & "END" & HT & "Scheduled" & NL
        & "BEGIN" & HT & "Completion" & NL
        & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
        & Completion_Line
        & "END" & HT & "Completion" & NL
        & "BEGIN" & HT & "Retirement" & NL
        & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
        & Retirement_Line
        & "END" & HT & "Retirement" & NL
        & "BEGIN" & HT & "Replacement" & NL
        & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
        & Replacement_Line
        & "END" & HT & "Replacement" & NL;
   end Lifecycle;

   function Empty_Actual return String is
   begin
      return "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL;
   end Empty_Actual;

   procedure Run is
   begin
      Reset_Root;
      Write_Atomically (Scheduled, Lifecycle);
      Write_Atomically (Actual, Empty_Actual);

      declare
         Actual_Before : constant String := Read_Exact (Actual);
         Published : constant Publish_Result :=
           Publish_Retirement
             (Root, (Token => Make_Token ("scheduled-1")));
         After : constant Read_Result := Read_File (Scheduled);
      begin
         Assert
           (Published.State = Retirement_Published_Fresh,
            "fresh canonical Scheduled retirement succeeds");
         Assert
           (After.Success
            and then After.Lifecycle.Ret_Count = 1
            and then Equal_Token
              (After.Lifecycle.Ret_Items (1).Scheduled.Token,
               Make_Token ("scheduled-1")),
            "retirement writer retains exact target");
         Assert
           (Read_Exact (Actual) = Actual_Before,
            "retirement does not rewrite Actual authority");
      end;

      declare
         Scheduled_Before : constant String := Read_Exact (Scheduled);
         Duplicate : constant Publish_Result :=
           Publish_Retirement
             (Root, (Token => Make_Token ("scheduled-1")));
      begin
         Assert
           (Duplicate.State = Retirement_Not_Published,
            "already retired Scheduled identity is rejected");
         Assert
           (Read_Exact (Scheduled) = Scheduled_Before,
            "duplicate retirement rewrites no Scheduled bytes");
      end;

      Reset_Root;
      Write_Atomically
        (Scheduled,
         Lifecycle
           (Completion_Line =>
              "COMPLETION" & HT & "scheduled-1" & HT
              & "scheduled-completion:scheduled-1" & NL));
      Write_Atomically (Actual, Empty_Actual);

      declare
         Before : constant String := Read_Exact (Scheduled);
         Interrupted : constant Publish_Result :=
           Publish_Retirement
             (Root, (Token => Make_Token ("scheduled-1")));
      begin
         Assert
           (Interrupted.State = Retirement_Not_Published,
            "interrupted completion blocks retirement");
         Assert
           (Interrupted.Error_Len > 0
            and then Index
              (Interrupted.Error_Reason (1 .. Interrupted.Error_Len),
               "interrupted completion") > 0,
            "interrupted completion rejection is explicit");
         Assert
           (Read_Exact (Scheduled) = Before,
            "interrupted completion rejection rewrites no Scheduled bytes");
      end;

      Reset_Root;
      Write_Atomically
        (Scheduled,
         Lifecycle
           (Completion_Line =>
              "COMPLETION" & HT & "scheduled-1" & HT
              & "scheduled-completion:scheduled-1" & NL));
      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "scheduled-completion:scheduled-1" & HT
         & "2026-09-23" & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-75" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "75" & NL
         & "ENDTX" & NL);

      declare
         Completed : constant Publish_Result :=
           Publish_Retirement
             (Root, (Token => Make_Token ("scheduled-1")));
      begin
         Assert
           (Completed.State = Retirement_Not_Published,
            "completed Scheduled identity cannot be retired");
         Assert
           (Completed.Error_Len > 0
            and then Index
              (Completed.Error_Reason (1 .. Completed.Error_Len),
               "already completed") > 0,
            "completed rejection is classified separately");
      end;

      Reset_Root;
      Write_Atomically
        (Scheduled,
         Lifecycle
           (Replacement_Line =>
              "REPLACEMENT" & HT & "scheduled-1" & HT
              & "scheduled-2" & NL));
      Write_Atomically (Actual, Empty_Actual);

      declare
         Replaced : constant Publish_Result :=
           Publish_Retirement
             (Root, (Token => Make_Token ("scheduled-1")));
      begin
         Assert
           (Replaced.State = Retirement_Not_Published,
            "replaced Scheduled identity cannot be retired");
      end;

      Assert
        (Ada.Directories.Exists (Scheduled & ".loam-writer-lock")
         and then Ada.Directories.Exists (Actual & ".loam-writer-lock"),
         "retirement uses shared Scheduled/Actual ownership anchors");
      Assert
        (not Ada.Directories.Exists (Scheduled & ".loam-stage"),
         "successful retirement consumes Scheduled sibling staging path");

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Retirement_Writer;
