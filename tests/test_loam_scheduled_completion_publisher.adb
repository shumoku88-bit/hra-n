with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Reader;
use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
use HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Completion_Publisher is

   package US renames Ada.Strings.Unbounded;

   Root      : constant String := "/tmp/hra_n_loam_scheduled_completion_publisher";
   Scheduled : constant String := Root & "/scheduled.loam";
   Actual    : constant String := Root & "/actual.loam";
   Policy    : constant String := Root & "/locus-admission.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "completion publisher fixture publishes atomically");
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

   function Base_Lifecycle return String is
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
        & "END" & HT & "Completion" & NL
        & "BEGIN" & HT & "Retirement" & NL
        & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
        & "END" & HT & "Retirement" & NL
        & "BEGIN" & HT & "Replacement" & NL
        & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
        & "END" & HT & "Replacement" & NL;
   end Base_Lifecycle;

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

   function Draft return Completion_Draft is
   begin
      return
        (Scheduled => (Token => Make_Token ("scheduled-1")),
         Has_Execution_Date => True,
         Execution_Date => (Year => 2026, Month => 9, Day => 24),
         Description => Make_Description ("groceries"));
   end Draft;

   procedure Assert_Effective is
      Lifecycle : constant Read_Result := Read_File (Scheduled);
      Actual_Image : constant Loam_Actual_Result :=
        Read_Loam_Actual_File (Actual);
      Date : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_Date : Boolean := False;
      Desc : Description_Text;
      Has_Desc : Boolean := False;
   begin
      Assert (Lifecycle.Success, "completed Scheduled lifecycle re-admits");
      Assert
        (Lifecycle.Success
         and then Lifecycle.Lifecycle.Comp_Count = 1,
         "effective completion retains one terminal claim");
      Assert
        (Lifecycle.Success
         and then Equal_Token
           (Lifecycle.Lifecycle.Comp_Items (1).Actual.Token,
            Make_Token ("scheduled-completion:scheduled-1")),
         "terminal claim retains deterministic Actual endpoint");

      Assert (Actual_Image.Success, "completed Actual authority re-admits");
      Assert_Equal_Int
        (1, Long_Long_Integer (Actual_Image.Events.Length),
         "completion publishes exactly one Actual Event");

      if Actual_Image.Events.Length = 1 then
         declare
            Item : constant Event := Actual_Image.Events.Element (1);
         begin
            Assert
              (Equal_Token
                 (HRA_N.Core.Event.Id (Item).Token,
                  Make_Token ("scheduled-completion:scheduled-1")),
               "Actual Event has deterministic completion identity");
            Assert_Equal_Int
              (2, Long_Long_Integer (Effect_Count (Item)),
               "Actual Event copies both planned physical Effects");
            Assert
              (Equal_Token
                 (Effect_At (Item, 1).Locus.Token, Make_Token ("cash"))
               and then Effect_At (Item, 1).Amount.Quanta = -75,
               "first Actual Effect matches Scheduled source");
            Assert
              (Equal_Token
                 (Effect_At (Item, 2).Locus.Token, Make_Token ("food"))
               and then Effect_At (Item, 2).Amount.Quanta = 75,
               "second Actual Effect matches Scheduled source");
         end;
      end if;

      Find_Occurrence_Date
        (Actual_Image.Validities,
         (Token => Make_Token ("scheduled-completion:scheduled-1")),
         Date,
         Has_Date);
      Assert
        (Has_Date
         and then Equal_Date
           (Date, (Year => 2026, Month => 9, Day => 24)),
         "completion retains requested execution date");

      Find_Description
        (Actual_Image.Descriptions,
         (Token => Make_Token ("scheduled-completion:scheduled-1")),
         Desc,
         Has_Desc);
      Assert
        (Has_Desc
         and then Equal_Description
           (Desc, Make_Description ("groceries")),
         "completion retains requested description");
   end Assert_Effective;

   procedure Run is
   begin
      Reset_Root;
      Write_Atomically (Scheduled, Base_Lifecycle);
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Policy, Good_Policy);

      declare
         Published : constant Publish_Result :=
           Publish_Completion (Root, Draft);
      begin
         Assert
           (Published.State = Completion_Published_Fresh_Claim,
            "fresh relation-first completion succeeds");
         Assert
           (Equal_Token
              (Published.Actual_Id.Token,
               Make_Token ("scheduled-completion:scheduled-1")),
            "fresh completion reports deterministic endpoint");
      end;
      Assert_Effective;

      --  Already effective completion is not silently duplicated.
      declare
         Scheduled_Before : constant String := Read_Exact (Scheduled);
         Actual_Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Completion (Root, Draft);
      begin
         Assert
           (Rejected.State = Completion_Not_Published,
            "already effective completion is rejected");
         Assert
           (Read_Exact (Scheduled) = Scheduled_Before
            and then Read_Exact (Actual) = Actual_Before,
            "already effective rejection rewrites neither authority");
      end;

      --  Force failure only at the Actual staging boundary.  The Scheduled
      --  claim must remain retained and inert, then the same endpoint must be
      --  reusable on retry.
      Reset_Root;
      Write_Atomically (Scheduled, Base_Lifecycle);
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Policy, Good_Policy);
      Ada.Directories.Create_Directory (Actual & ".loam-stage");

      declare
         Interrupted : constant Publish_Result :=
           Publish_Completion (Root, Draft);
         Lifecycle : constant Read_Result := Read_File (Scheduled);
         Actual_Image : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
      begin
         Assert
           (Interrupted.State = Completion_Claim_Inert,
            "Actual staging failure leaves explicit inert completion state");
         Assert
           (Lifecycle.Success
            and then Lifecycle.Lifecycle.Comp_Count = 1
            and then Equal_Token
              (Lifecycle.Lifecycle.Comp_Items (1).Actual.Token,
               Make_Token ("scheduled-completion:scheduled-1")),
            "interruption retains exact Scheduled completion claim");
         Assert
           (Actual_Image.Success
            and then Actual_Image.Events.Length = 0,
            "interruption does not expose partial Actual Event");
      end;

      Ada.Directories.Delete_Tree (Actual & ".loam-stage");

      declare
         Retried : constant Publish_Result :=
           Publish_Completion (Root, Draft);
      begin
         Assert
           (Retried.State = Completion_Published_Resumed_Claim,
            "retry resumes retained inert claim");
         Assert
           (Equal_Token
              (Retried.Actual_Id.Token,
               Make_Token ("scheduled-completion:scheduled-1")),
            "retry preserves deterministic endpoint");
      end;
      Assert_Effective;

      Assert
        (Ada.Directories.Exists (Scheduled & ".loam-writer-lock")
         and then Ada.Directories.Exists (Actual & ".loam-writer-lock"),
         "publisher uses the ordered Scheduled/Actual ownership anchors");
      Assert
        (not Ada.Directories.Exists (Scheduled & ".loam-stage")
         and then not Ada.Directories.Exists (Actual & ".loam-stage"),
         "successful completion consumes both sibling staging paths");

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Completion_Publisher;
