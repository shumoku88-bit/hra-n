with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Scheduled_Creation_Writer;
use HRA_N.Storage.Loam_Scheduled_Creation_Writer;
with HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
use HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
with Test_Support; use Test_Support;

package body Test_Loam_Scheduled_Creation_Writer is

   package US renames Ada.Strings.Unbounded;

   Root      : constant String := "/tmp/hra_n_loam_scheduled_creation_writer";
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
         "Scheduled creation fixture publishes atomically");
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

   function Base_Lifecycle return String is
   begin
      return
        "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
        & "BEGIN" & HT & "Scheduled" & NL
        & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
        & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
        & "CHANGE" & HT & "cash" & HT & "-10" & NL
        & "CHANGE" & HT & "food" & HT & "10" & NL
        & "SCHEDULED" & HT & "scheduled-3" & HT & "2026-09-21" & HT & "jpy" & NL
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

   function Draft
     (Measure : String := "jpy";
      To_Name : String := "food";
      Left    : Quanta_Type := -125;
      Right   : Quanta_Type := 125) return Creation_Draft
   is
      Changes : Change_List;
   begin
      Changes.Count := 2;
      Changes.Values (1) :=
        (Locus => (Token => Make_Token ("cash")), Amount => Left);
      Changes.Values (2) :=
        (Locus => (Token => Make_Token (To_Name)), Amount => Right);
      return
        (Expected_Day => (Year => 2026, Month => 9, Day => 22),
         Measure      => (Token => Make_Token (Measure)),
         Changes      => Changes);
   end Draft;

   procedure Run is
   begin
      Reset_Root;
      Write_Atomically (Actual, Empty_Actual);
      Write_Atomically (Policy, Good_Policy);
      Write_Atomically (Scheduled, Base_Lifecycle);

      declare
         Published : constant Publish_Result :=
           Publish_Creation (Root, Draft);
      begin
         Assert
           (Published.Success,
            "canonical Scheduled creation publication succeeds");
         Assert
           (Published.Success
            and then Equal_Token
              (Published.Scheduled_Id.Token,
               Make_Token ("scheduled-2")),
            "writer follows Loam first-unused scheduled-N identity allocation");
      end;

      declare
         Image : constant Read_Result := Read_File (Scheduled);
      begin
         Assert
           (Image.Success,
            "published complete Scheduled lifecycle re-admits");
         if Image.Success then
            Assert_Equal_Int
              (3, Long_Long_Integer (Image.Lifecycle.Sched_Count),
               "publication preserves prior occurrences and adds exactly one");
            Assert_Equal_Int
              (1, Long_Long_Integer (Image.Lifecycle.Ret_Count),
               "publication preserves prior terminal evidence");
            Assert
              (Is_Retired
                 (Image.Lifecycle,
                  (Token => Make_Token ("scheduled-1"))),
               "prior retirement remains intact");

            declare
               Added : constant Lookup_Result :=
                 Find_Occurrence
                   (Image.Lifecycle,
                    (Token => Make_Token ("scheduled-2")));
            begin
               Assert (Added.Found, "fresh Scheduled identity is retained");
               if Added.Found then
                  Assert
                    (Equal_Date
                       (Added.Item.Expected_Day,
                        (Year => 2026, Month => 9, Day => 22)),
                     "fresh Scheduled occurrence date is exact");
                  Assert
                    (Equal_Token
                       (Added.Item.Measure.Token, Make_Token ("jpy")),
                     "fresh Scheduled Measure is exact");
                  Assert_Equal_Int
                    (2, Long_Long_Integer (Added.Item.Changes.Count),
                     "fresh Scheduled movement retains both changes");
                  Assert_Equal_Int
                    (-125,
                     Long_Long_Integer
                       (Added.Item.Changes.Values (1).Amount),
                     "fresh Scheduled FROM change is exact");
                  Assert_Equal_Int
                    (125,
                     Long_Long_Integer
                       (Added.Item.Changes.Values (2).Amount),
                     "fresh Scheduled TO change is exact");
               end if;
            end;
         end if;
      end;

      Assert
        (not Ada.Directories.Exists (Scheduled & ".loam-stage"),
         "successful Scheduled authority switch consumes sibling stage");
      Assert
        (Ada.Directories.Exists (Scheduled & ".loam-writer-lock"),
         "writer uses Scheduled ownership anchor");
      Assert
        (Ada.Directories.Exists (Actual & ".loam-writer-lock"),
         "writer shares Actual ownership anchor in Loam order");

      declare
         Before : constant String := Read_Exact (Scheduled);
         Rejected : constant Publish_Result :=
           Publish_Creation (Root, Draft (To_Name => "unapproved"));
      begin
         Assert
           (not Rejected.Success
            and then Rejected.Status = Locus_Not_Admitted,
            "unapproved Scheduled Locus fails closed");
         Assert
           (Format_Error (Rejected) =
              "Scheduled creation uses a Locus not approved for new publication",
            "format error matches Locus_Not_Admitted message");
         Assert
           (Read_Exact (Scheduled) = Before,
            "policy rejection leaves Scheduled authority untouched");
      end;

      declare
         Before : constant String := Read_Exact (Scheduled);
         Rejected : constant Publish_Result :=
           Publish_Creation (Root, Draft (Measure => "usd"));
      begin
         Assert
           (not Rejected.Success
            and then Rejected.Status = Unsupported_Measure,
            "current canonical Scheduled creation refuses non-JPY movement");
         Assert
           (Format_Error (Rejected) =
              "Scheduled creation currently requires Measure jpy",
            "format error matches Unsupported_Measure message");
         Assert
           (Read_Exact (Scheduled) = Before,
            "Measure rejection leaves Scheduled authority untouched");
      end;

      declare
         Before : constant String := Read_Exact (Scheduled);
         Rejected : constant Publish_Result :=
           Publish_Creation
             (Root, Draft (Left => -125, Right => 124));
      begin
         Assert
           (not Rejected.Success
            and then Rejected.Status = Unconserved_Changes,
            "unbalanced Scheduled creation fails closed");
         Assert
           (Format_Error (Rejected) =
              "Scheduled creation changes must conserve exactly",
            "format error matches Unconserved_Changes message");
         Assert
           (Read_Exact (Scheduled) = Before,
            "balance rejection leaves Scheduled authority untouched");
      end;

      declare
         Zero_Draft : Creation_Draft := Draft;
         Before : constant String := Read_Exact (Scheduled);
      begin
         Zero_Draft.Changes.Values (1).Amount := 0;
         Zero_Draft.Changes.Values (2).Amount := 0;
         declare
            Rejected : constant Publish_Result :=
              Publish_Creation (Root, Zero_Draft);
         begin
            Assert
              (not Rejected.Success
               and then Rejected.Status = Invalid_Change_Token_Or_Zero,
               "zero-quantity Scheduled changes fail closed like Loam publisher");
            Assert
              (Format_Error (Rejected) =
                 "Scheduled creation requires valid Locus tokens and nonzero quantities",
               "format error matches Invalid_Change_Token_Or_Zero message");
            Assert
              (Read_Exact (Scheduled) = Before,
               "zero-quantity rejection leaves Scheduled authority untouched");
         end;
      end;

      --  Raw lifecycle decoding deliberately preserves cross-kind conflict,
      --  but a publisher must not extend an application-unreadable authority.
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
         & "END" & HT & "Completion" & NL
         & "BEGIN" & HT & "Retirement" & NL
         & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
         & "RETIREMENT" & HT & "scheduled-1" & NL
         & "END" & HT & "Retirement" & NL
         & "BEGIN" & HT & "Replacement" & NL
         & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
         & "REPLACEMENT" & HT & "scheduled-1" & HT & "scheduled-2" & NL
         & "END" & HT & "Replacement" & NL);

      declare
         Raw : constant Read_Result := Read_File (Scheduled);
         Before : constant String := Read_Exact (Scheduled);
         Rejected : Publish_Result;
      begin
         Assert
           (Raw.Success,
            "raw lifecycle reader retains cross-kind terminal conflict");
         Rejected := Publish_Creation (Root, Draft);
         Assert
           (not Rejected.Success
            and then Rejected.Status = Lifecycle_Not_Readable,
            "Scheduled writer refuses cross-kind terminal conflict");
         Assert
           (Format_Error (Rejected) =
              "current Scheduled lifecycle is not application-readable",
            "format error matches Lifecycle_Not_Readable message");
         Assert
           (Read_Exact (Scheduled) = Before,
            "terminal conflict leaves Scheduled authority untouched");
      end;

      --  Input validation checks
      declare
         Empty_Root_Res : constant Publish_Result :=
           Publish_Creation ("", Draft);
         Bad_Date_Draft : Creation_Draft := Draft;
         Empty_Changes_Draft : Creation_Draft := Draft;
      begin
         Bad_Date_Draft.Expected_Day := (Year => 2026, Month => 2, Day => 30);
         Empty_Changes_Draft.Changes.Count := 0;
         declare
            Bad_Date_Res : constant Publish_Result :=
              Publish_Creation (Root, Bad_Date_Draft);
            Empty_Changes_Res : constant Publish_Result :=
              Publish_Creation (Root, Empty_Changes_Draft);
         begin
            Assert
              (not Empty_Root_Res.Success
               and then Empty_Root_Res.Status = Invalid_Root_Directory,
               "empty root yields Invalid_Root_Directory");
            Assert
              (not Bad_Date_Res.Success
               and then Bad_Date_Res.Status = Invalid_Occurrence_Date,
               "bad date yields Invalid_Occurrence_Date");
            Assert
              (not Empty_Changes_Res.Success
               and then Empty_Changes_Res.Status = Empty_Changes,
               "empty changes yields Empty_Changes");
         end;
      end;

      --  A missing Actual completion endpoint is intentionally inert in
      --  Loam: the Scheduled source remains open so interrupted completion
      --  publication can be retried. Creation must preserve and extend it.
      Write_Atomically
        (Scheduled,
         "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
         & "BEGIN" & HT & "Scheduled" & NL
         & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
         & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
         & "CHANGE" & HT & "cash" & HT & "-10" & NL
         & "CHANGE" & HT & "food" & HT & "10" & NL
         & "END" & HT & "Scheduled" & NL
         & "BEGIN" & HT & "Completion" & NL
         & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
         & "COMPLETION" & HT & "scheduled-1" & HT & "record-missing" & NL
         & "END" & HT & "Completion" & NL
         & "BEGIN" & HT & "Retirement" & NL
         & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
         & "END" & HT & "Retirement" & NL
         & "BEGIN" & HT & "Replacement" & NL
         & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
         & "END" & HT & "Replacement" & NL);

      declare
         Published : constant Publish_Result :=
           Publish_Creation (Root, Draft);
         Image : Read_Result;
      begin
         Assert
           (Published.Success,
            "missing completion Actual remains inert during Scheduled creation");
         Image := Read_File (Scheduled);
         Assert
           (Image.Success
            and then Completion_Mentions_Actual
              (Image, (Token => Make_Token ("record-missing"))),
            "inert completion evidence is preserved after creation");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Scheduled_Creation_Writer;
