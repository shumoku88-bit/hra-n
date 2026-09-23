with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Scheduled_Completion_Writer;
use HRA_N.Storage.Loam_Scheduled_Completion_Writer;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Completion_Writer is

   package US renames Ada.Strings.Unbounded;

   Root      : constant String := "/tmp/hra_n_loam_scheduled_completion_writer";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "Scheduled completion fixture publishes atomically");
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

   function Empty_Actual return String is
   begin
      return "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL;
   end Empty_Actual;

   function Base_Lifecycle return String is
   begin
      return
        "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
        & "BEGIN" & HT & "Scheduled" & NL
        & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
        & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
        & "CHANGE" & HT & "cash" & HT & "-10" & NL
        & "CHANGE" & HT & "food" & HT & "10" & NL
        & "SCHEDULED" & HT & "scheduled-2" & HT & "2026-09-21" & HT & "jpy" & NL
        & "CHANGE" & HT & "cash" & HT & "-20" & NL
        & "CHANGE" & HT & "food" & HT & "20" & NL
        & "END" & HT & "Scheduled" & NL
        & "BEGIN" & HT & "Completion" & NL
        & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
        & "END" & HT & "Completion" & NL
        & "BEGIN" & HT & "Retirement" & NL
        & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
        & "RETIREMENT" & HT & "scheduled-1" & NL
        & "END" & HT & "Retirement" & NL
        & "BEGIN" & HT & "Replacement" & NL
        & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
        & "END" & HT & "Replacement" & NL;
   end Base_Lifecycle;

   function Actual_With_Completion_Event return String is
   begin
      return
        "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
        & "TX" & HT & "scheduled-completion:scheduled-2"
        & HT & "2026-09-23" & HT & "NODESC" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-20" & NL
        & "EFFECT" & HT & "food" & HT & "jpy" & HT & "20" & NL
        & "ENDTX" & NL;
   end Actual_With_Completion_Event;

   procedure Run is
      Target : constant Scheduled_Id :=
        (Token => Make_Token ("scheduled-2"));
   begin
      Reset_Root;
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Scheduled, Base_Lifecycle);

      declare
         Before_Actual : constant String := Read_Exact (Actual);
         Published : constant Publish_Result :=
           Publish_Completion_Claim (Root, Target);
      begin
         Assert
           (Published.State = Claim_Published_Fresh,
            "fresh canonical Scheduled completion claim publishes");
         Assert
           (Equal_Token
              (Published.Actual_Id.Token,
               Make_Token ("scheduled-completion:scheduled-2")),
            "writer derives Loam-compatible deterministic Actual endpoint");
         Assert
           (Read_Exact (Actual) = Before_Actual,
            "claim-only publication does not create the Actual Event");
      end;

      declare
         Image : constant Read_Result := Read_File (Scheduled);
      begin
         Assert
           (Image.Success,
            "Scheduled lifecycle re-admits after completion claim");
         Assert_Equal_Int
           (1, Long_Long_Integer (Image.Lifecycle.Comp_Count),
            "fresh claim adds exactly one completion relation");
         Assert
           (Equal_Token
              (Image.Lifecycle.Comp_Items (1).Scheduled.Token,
               Make_Token ("scheduled-2"))
            and then Equal_Token
              (Image.Lifecycle.Comp_Items (1).Actual.Token,
               Make_Token ("scheduled-completion:scheduled-2")),
            "retained completion relation is exact");
         Assert_Equal_Int
           (2, Long_Long_Integer (Image.Lifecycle.Sched_Count),
            "claim publication preserves Scheduled occurrences");
         Assert_Equal_Int
           (1, Long_Long_Integer (Image.Lifecycle.Ret_Count),
            "claim publication preserves retirement evidence");
      end;

      declare
         Before : constant String := Read_Exact (Scheduled);
         Retry : constant Publish_Result :=
           Publish_Completion_Claim (Root, Target);
      begin
         Assert
           (Retry.State = Claim_Already_Inert,
            "same retained claim with missing Actual is reusable for retry");
         Assert
           (Read_Exact (Scheduled) = Before,
            "inert retry does not rewrite Scheduled authority");
      end;

      Write_Atomically (Actual, Actual_With_Completion_Event);
      declare
         Before : constant String := Read_Exact (Scheduled);
         Rejected : constant Publish_Result :=
           Publish_Completion_Claim (Root, Target);
      begin
         Assert
           (Rejected.State = Claim_Not_Ready,
            "effective completion cannot be claimed again");
         Assert
           (Read_Exact (Scheduled) = Before,
            "already-completed rejection leaves Scheduled authority untouched");
      end;

      Reset_Root;
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Scheduled, Base_Lifecycle);
      declare
         Before : constant String := Read_Exact (Scheduled);
         Rejected : constant Publish_Result :=
           Publish_Completion_Claim
             (Root, (Token => Make_Token ("scheduled-1")));
      begin
         Assert
           (Rejected.State = Claim_Not_Ready,
            "retired Scheduled identity cannot receive completion claim");
         Assert
           (Read_Exact (Scheduled) = Before,
            "retirement rejection leaves Scheduled authority untouched");
      end;

      Write_Atomically
        (Scheduled,
         "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
         & "BEGIN" & HT & "Scheduled" & NL
         & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
         & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
         & "CHANGE" & HT & "cash" & HT & "-10" & NL
         & "CHANGE" & HT & "food" & HT & "10" & NL
         & "SCHEDULED" & HT & "scheduled-2" & HT & "2026-09-21" & HT & "jpy" & NL
         & "CHANGE" & HT & "cash" & HT & "-20" & NL
         & "CHANGE" & HT & "food" & HT & "20" & NL
         & "END" & HT & "Scheduled" & NL
         & "BEGIN" & HT & "Completion" & NL
         & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
         & "COMPLETION" & HT & "scheduled-1"
         & HT & "scheduled-completion:scheduled-2" & NL
         & "END" & HT & "Completion" & NL
         & "BEGIN" & HT & "Retirement" & NL
         & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
         & "END" & HT & "Retirement" & NL
         & "BEGIN" & HT & "Replacement" & NL
         & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
         & "END" & HT & "Replacement" & NL);

      declare
         Before : constant String := Read_Exact (Scheduled);
         Rejected : constant Publish_Result :=
           Publish_Completion_Claim (Root, Target);
      begin
         Assert
           (Rejected.State = Claim_Not_Ready,
            "Actual completion endpoint owned by another Scheduled source is rejected");
         Assert
           (Read_Exact (Scheduled) = Before,
            "endpoint-ownership rejection leaves Scheduled authority untouched");
      end;

      Assert
        (not Ada.Directories.Exists (Scheduled & ".loam-stage"),
         "Scheduled completion publication leaves no sibling stage");
      Assert
        (Ada.Directories.Exists (Scheduled & ".loam-writer-lock"),
         "completion writer uses Scheduled ownership anchor");
      Assert
        (Ada.Directories.Exists (Actual & ".loam-writer-lock"),
         "completion writer shares Actual ownership anchor");

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Completion_Writer;
