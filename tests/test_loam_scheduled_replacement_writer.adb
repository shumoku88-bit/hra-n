with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with HRA_N.Storage.Loam_Scheduled_Replacement_Writer;
use HRA_N.Storage.Loam_Scheduled_Replacement_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Replacement_Writer is

   package US renames Ada.Strings.Unbounded;

   Root      : constant String := "/tmp/hra_n_loam_scheduled_replacement_writer";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";
   Policy    : constant String := Root & "/locus-admission.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "replacement writer fixture publishes atomically");
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

   function Good_Policy return String is
   begin
      return
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
        & "LOCUS" & HT & "cash" & NL
        & "LOCUS" & HT & "food" & NL;
   end Good_Policy;

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

   function Draft
     (To_Name : String := "food";
      Left    : Quanta_Type := -90;
      Right   : Quanta_Type := 90) return Replacement_Draft
   is
      Changes : Change_List;
   begin
      Changes.Count := 2;
      Changes.Values (1) :=
        (Locus => (Token => Make_Token ("cash")), Amount => Left);
      Changes.Values (2) :=
        (Locus => (Token => Make_Token (To_Name)), Amount => Right);
      return
        (Source       => (Token => Make_Token ("scheduled-1")),
         Expected_Day => (Year => 2026, Month => 9, Day => 25),
         Measure      => (Token => Make_Token ("jpy")),
         Changes      => Changes);
   end Draft;

   procedure Run is
   begin
      Reset_Root;
      Write_Atomically (Scheduled, Lifecycle);
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Policy, Good_Policy);

      declare
         Actual_Before : constant String := Read_Exact (Actual);
         Published : constant Publish_Result :=
           Publish_Replacement (Root, Draft);
         After : constant Read_Result := Read_File (Scheduled);
      begin
         Assert
           (Published.Success,
            "fresh canonical Scheduled replacement succeeds");
         Assert
           (Published.Success
            and then Equal_Token
              (Published.Replacement_Id.Token,
               Make_Token ("scheduled-2")),
            "replacement allocates first unused Scheduled identity");
         Assert
           (After.Success,
            "replacement lifecycle re-admits after publication");

         if After.Success then
            Assert_Equal_Int
              (2, Long_Long_Integer (After.Lifecycle.Sched_Count),
               "replacement adds exactly one Scheduled occurrence");
            Assert_Equal_Int
              (1, Long_Long_Integer (After.Lifecycle.Repl_Count),
               "replacement adds exactly one relation");
            Assert
              (Equal_Token
                 (After.Lifecycle.Repl_Items (1).Original.Token,
                  Make_Token ("scheduled-1"))
               and then Equal_Token
                 (After.Lifecycle.Repl_Items (1).Replaced_By.Token,
                  Make_Token ("scheduled-2")),
               "replacement relation retains exact endpoints");
            Assert
              (not Is_Current_Open
                 (After.Lifecycle,
                  (Token => Make_Token ("scheduled-1")))
               and then Is_Current_Open
                 (After.Lifecycle,
                  (Token => Make_Token ("scheduled-2"))),
               "replacement closes source and opens successor");
         end if;

         Assert
           (Read_Exact (Actual) = Actual_Before,
            "replacement does not rewrite Actual authority");
      end;

      Assert
        (not Ada.Directories.Exists (Scheduled & ".loam-stage"),
         "successful replacement consumes Scheduled sibling stage");
      Assert
        (Ada.Directories.Exists (Scheduled & ".loam-writer-lock")
         and then Ada.Directories.Exists (Actual & ".loam-writer-lock"),
         "replacement uses shared Scheduled/Actual ownership anchors");

      declare
         Before : constant String := Read_Exact (Scheduled);
         Duplicate : constant Publish_Result :=
           Publish_Replacement (Root, Draft);
      begin
         Assert
           (not Duplicate.Success,
            "already replaced Scheduled source is rejected");
         Assert
           (Duplicate.Status = Source_Not_Current_Open,
            "duplicate replacement reports source not current open");
         Assert
           (Format_Error (Duplicate) =
              "selected Scheduled identity is no longer current-open",
            "duplicate replacement formats error");
         Assert
           (Read_Exact (Scheduled) = Before,
            "stale replacement rewrites no Scheduled bytes");
      end;

      Reset_Root;
      Write_Atomically (Scheduled, Lifecycle);
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Policy, Good_Policy);

      declare
         Before : constant String := Read_Exact (Scheduled);
         Rejected : constant Publish_Result :=
           Publish_Replacement (Root, Draft (To_Name => "unapproved"));
      begin
         Assert
           (not Rejected.Success,
            "replacement Locus outside admission vocabulary fails closed");
         Assert
           (Rejected.Status = Locus_Not_Approved,
            "unapproved locus reports locus not approved status");
         Assert
           (Format_Error (Rejected) =
              "Scheduled replacement uses a Locus not approved for new publication",
            "unapproved locus formats error");
         Assert
           (Read_Exact (Scheduled) = Before,
            "Locus rejection leaves Scheduled authority untouched");
      end;

      Reset_Root;
      Write_Atomically
        (Scheduled,
         Lifecycle
           (Completion_Line =>
              "COMPLETION" & HT & "scheduled-1" & HT
              & "scheduled-completion:scheduled-1" & NL));
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Policy, Good_Policy);

      declare
         Before : constant String := Read_Exact (Scheduled);
         Interrupted : constant Publish_Result :=
           Publish_Replacement (Root, Draft);
      begin
         Assert
           (not Interrupted.Success,
            "interrupted completion claim blocks HRA-N replacement");
         Assert
           (Interrupted.Status = Interrupted_Completion,
            "interrupted completion reports status");
         Assert
           (Format_Error (Interrupted) =
              "selected Scheduled identity has an interrupted completion; retry completion before replacement",
            "interrupted completion formats error");
         Assert
           (Read_Exact (Scheduled) = Before,
            "interrupted completion refusal rewrites no Scheduled bytes");
      end;

      Reset_Root;
      Write_Atomically
        (Scheduled,
         Lifecycle
           (Retirement_Line =>
              "RETIREMENT" & HT & "scheduled-1" & NL));
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Policy, Good_Policy);

      declare
         Retired : constant Publish_Result :=
           Publish_Replacement (Root, Draft);
      begin
         Assert
           (not Retired.Success,
            "retired Scheduled source cannot be replaced");
         Assert
           (Retired.Status = Source_Not_Current_Open,
            "retired source reports source not current open");
         Assert
           (Format_Error (Retired) =
              "selected Scheduled identity is no longer current-open",
            "retired source formats error");
      end;

      declare
         Empty_Root_Result : constant Publish_Result :=
           Publish_Replacement ("", Draft);
      begin
         Assert
           (not Empty_Root_Result.Success,
            "empty root directory is rejected");
         Assert
           (Empty_Root_Result.Status = Invalid_Root_Directory,
            "invalid root directory status reported");
         Assert
           (Format_Error (Empty_Root_Result) =
              "LOAM data root must not be empty",
            "invalid root directory error formatted");
      end;

      declare
         Bad_Draft : Replacement_Draft := Draft;
         Invalid_Token_Result : Publish_Result;
      begin
         Bad_Draft.Source.Token := (Length => 0, Value => [others => ' ']);
         Invalid_Token_Result := Publish_Replacement (Root, Bad_Draft);
         Assert
           (not Invalid_Token_Result.Success,
            "invalid source token is rejected");
         Assert
           (Invalid_Token_Result.Status = Invalid_Source_Token,
            "invalid source token status reported");
         Assert
           (Format_Error (Invalid_Token_Result) =
              "Scheduled replacement requires a valid source identity",
            "invalid source token error formatted");
      end;

      declare
         Unconserved_Result : constant Publish_Result :=
           Publish_Replacement (Root, Draft (Left => -90, Right => 80));
      begin
         Assert
           (not Unconserved_Result.Success,
            "unconserved draft is rejected");
         Assert
           (Unconserved_Result.Status = Changes_Not_Conserved,
            "unconserved status reported");
         Assert
           (Format_Error (Unconserved_Result) =
              "Scheduled replacement changes must conserve exactly",
            "unconserved error formatted");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Replacement_Writer;
