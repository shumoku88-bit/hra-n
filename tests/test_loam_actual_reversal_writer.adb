with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Writer; use HRA_N.Storage.Loam_Actual_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Actual_Reversal_Writer is

   package US renames Ada.Strings.Unbounded;

   Root      : constant String := "/tmp/hra_n_loam_actual_reversal_writer";
   Actual    : constant String := Root & "/actual.loam";
   Scheduled : constant String := Root & "/scheduled.loam";
   Policy    : constant String := Root & "/locus-admission.loam";
   HT        : constant String := [1 => ASCII.HT];
   NL        : constant String := [1 => ASCII.LF];

   function Empty_Scheduled return String is
   begin
      return
        "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
        & "BEGIN" & HT & "Scheduled" & NL
        & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
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
   end Empty_Scheduled;

   function Completed_Scheduled return String is
   begin
      return
        "LOAM-SCHEDULED-LIFECYCLE" & HT & "1" & NL
        & "BEGIN" & HT & "Scheduled" & NL
        & "LOAM-SCHEDULED-MEMORY" & HT & "1" & NL
        & "SCHEDULED" & HT & "scheduled-1" & HT & "2026-09-20" & HT & "jpy" & NL
        & "CHANGE" & HT & "cash" & HT & "-120" & NL
        & "CHANGE" & HT & "food" & HT & "120" & NL
        & "END" & HT & "Scheduled" & NL
        & "BEGIN" & HT & "Completion" & NL
        & "LOAM-SCHEDULED-COMPLETION-MEMORY" & HT & "1" & NL
        & "COMPLETION" & HT & "scheduled-1" & HT & "record-1" & NL
        & "END" & HT & "Completion" & NL
        & "BEGIN" & HT & "Retirement" & NL
        & "LOAM-SCHEDULED-RETIREMENT-MEMORY" & HT & "1" & NL
        & "END" & HT & "Retirement" & NL
        & "BEGIN" & HT & "Replacement" & NL
        & "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & HT & "1" & NL
        & "END" & HT & "Replacement" & NL;
   end Completed_Scheduled;

   function Base_Actual (Measure : String := "jpy") return String is
   begin
      return
        "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
        & "TX" & HT & "record-1" & HT & "2026-09-20"
        & HT & "DESC" & HT & "retained target" & NL
        & "EFFECT" & HT & "cash" & HT & Measure & HT & "-120" & NL
        & "EFFECT" & HT & "food" & HT & Measure & HT & "120" & NL
        & "ENDTX" & NL;
   end Base_Actual;

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "reversal fixture publishes atomically");
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

   procedure Reset_Root
     (Actual_Text    : String := Base_Actual;
      Scheduled_Text : String := Empty_Scheduled;
      Policy_Text    : String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
        & "LOCUS" & HT & "cash" & NL
        & "LOCUS" & HT & "food" & NL)
   is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
      Write_Atomically (Actual, Actual_Text);
      Write_Atomically (Scheduled, Scheduled_Text);
      Write_Atomically (Policy, Policy_Text);
   end Reset_Root;

   procedure Run is
   begin
      --  Canonical happy path: deterministic identity, fresh occurrence date,
      --  anonymous exact inverse Effects, retained target, no supersession.
      Reset_Root;
      declare
         Before : constant String := Read_Exact (Actual);
         Published : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
         After : constant String := Read_Exact (Actual);
      begin
         Assert (Published.Success, "canonical reversal publication succeeds");
         Assert
           (Published.Success
            and then Equal_Token
              (Published.Event_Id,
               Make_Token ("actual-reversal:record-1")),
            "reversal identity is deterministic from target identity");
         Assert
           (After'Length > Before'Length
            and then Index (After, Before) = After'First,
            "reversal publication retains the prior canonical byte prefix");

         declare
            Image : constant Loam_Actual_Result :=
              Read_Loam_Actual_File (Actual);
            Reverser : Event_Id;
            Has_Reverser : Boolean;
            Successor : Event_Id;
            Has_Successor : Boolean;
            Reversal_Date : Date_Type;
            Has_Date : Boolean;
            Desc : Description_Text;
            Has_Desc : Boolean;
            Target_Event : constant Event := Image.Events.Element (1);
            Reversal_Event : constant Event := Image.Events.Element (2);
         begin
            Assert (Image.Success, "published reversal re-admits");
            Assert_Equal_Int
              (2, Long_Long_Integer (Image.Events.Length),
               "reversal appends exactly one Event");
            Assert
              (Equal_Token
                 (HRA_N.Core.Event.Id (Target_Event).Token,
                  Make_Token ("record-1"))
               and then Effect_At (Target_Event, 1).Amount.Quanta = -120
               and then Effect_At (Target_Event, 2).Amount.Quanta = 120,
               "target Event remains retained unchanged");
            Assert
              (Equal_Token
                 (HRA_N.Core.Event.Id (Reversal_Event).Token,
                  Make_Token ("actual-reversal:record-1")),
               "appended Event has deterministic reversal identity");
            Assert
              (not Effect_At (Reversal_Event, 1).Key.Present
               and then not Effect_At (Reversal_Event, 2).Key.Present,
               "reversal Effect identity is anonymous");
            Assert
              (Equal_Token
                 (Effect_At (Reversal_Event, 1).Locus.Token,
                  Make_Token ("cash"))
               and then Effect_At (Reversal_Event, 1).Amount.Quanta = 120
               and then Equal_Token
                 (Effect_At (Reversal_Event, 2).Locus.Token,
                  Make_Token ("food"))
               and then Effect_At (Reversal_Event, 2).Amount.Quanta = -120,
               "reversal Effects are the exact additive inverse");
            Find_Reverser
              (Image.Metadata,
               (Token => Make_Token ("record-1")),
               Reverser,
               Has_Reverser);
            Assert
              (Has_Reverser
               and then Equal_Token
                 (Reverser.Token,
                  Make_Token ("actual-reversal:record-1")),
               "REVERSAL-OF provenance names the retained target");
            Find_Successor
              (Image.Metadata,
               (Token => Make_Token ("record-1")),
               Successor,
               Has_Successor);
            Assert
              (not Has_Successor,
               "reversal does not supersede the target");
            Find_Occurrence_Date
              (Image.Validities,
               (Token => Make_Token ("actual-reversal:record-1")),
               Reversal_Date,
               Has_Date);
            Assert
              (Has_Date
               and then Equal_Date
                 (Reversal_Date, (Year => 2026, Month => 9, Day => 22)),
               "reversal keeps its independently supplied occurrence date");
            Find_Description
              (Image.Descriptions,
               (Token => Make_Token ("actual-reversal:record-1")),
               Desc,
               Has_Desc);
            Assert
              (not Has_Desc,
               "reversal does not synthesize target description");
         end;

         declare
            Stable : constant String := Read_Exact (Actual);
            Again : constant Publish_Result :=
              Publish_Reversal
                (Root,
                 (Token => Make_Token ("record-1")),
                 (Year => 2026, Month => 9, Day => 23));
            Chain : constant Publish_Result :=
              Publish_Reversal
                (Root,
                 (Token => Make_Token ("actual-reversal:record-1")),
                 (Year => 2026, Month => 9, Day => 23));
         begin
            Assert
              (not Again.Success,
               "already reversed target is refused");
            Assert
              (not Chain.Success,
               "reversal-of-reversal is refused");
            Assert
              (Read_Exact (Actual) = Stable,
               "reversal topology refusals leave authority unchanged");
         end;
      end;

      --  A correction target is no longer current and cannot be reversed.
      Reset_Root
        (Actual_Text =>
           Base_Actual
           & "TX" & HT & "replacement-1" & HT & "2026-09-20"
           & HT & "NODESC" & NL
           & "REPLACES" & HT & "record-1" & NL
           & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-130" & NL
           & "EFFECT" & HT & "food" & HT & "jpy" & HT & "130" & NL
           & "ENDTX" & NL);
      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
      begin
         Assert (not Rejected.Success, "non-current correction target is refused");
         Assert
           (Read_Exact (Actual) = Before,
            "non-current refusal leaves authority unchanged");
      end;

      --  Scheduled-completion provenance is a separate authority guard.
      Reset_Root (Scheduled_Text => Completed_Scheduled);
      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
      begin
         Assert
           (not Rejected.Success,
            "Scheduled-completion Actual is refused");
         Assert
           (Read_Exact (Actual) = Before,
            "Scheduled guard refusal leaves Actual authority unchanged");
      end;

      --  Missing/malformed Scheduled authority fails closed.
      Reset_Root (Scheduled_Text => "not-a-lifecycle" & NL);
      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
      begin
         Assert
           (not Rejected.Success,
            "malformed Scheduled lifecycle fails reversal closed");
         Assert
           (Read_Exact (Actual) = Before,
            "malformed Scheduled refusal leaves Actual unchanged");
      end;

      --  Practical entrance remains exactly balanced JPY.
      Reset_Root (Actual_Text => Base_Actual ("usd"));
      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
      begin
         Assert (not Rejected.Success, "non-JPY target is refused");
         Assert
           (Read_Exact (Actual) = Before,
            "non-JPY refusal leaves authority unchanged");
      end;

      --  Current Locus admission vocabulary governs the newly published inverse.
      Reset_Root
        (Policy_Text =>
           "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
           & "LOCUS" & HT & "cash" & NL);
      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
      begin
         Assert (not Rejected.Success, "unapproved inverse Locus is refused");
         Assert
           (Read_Exact (Actual) = Before,
            "Locus admission refusal leaves authority unchanged");
      end;

      --  Deterministic identity collision is not replaced by a fresh fallback.
      Reset_Root
        (Actual_Text =>
           Base_Actual
           & "TX" & HT & "actual-reversal:record-1" & HT & "2026-09-21"
           & HT & "NODESC" & NL
           & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-5" & NL
           & "EFFECT" & HT & "food" & HT & "jpy" & HT & "5" & NL
           & "ENDTX" & NL);
      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
      begin
         Assert
           (not Rejected.Success,
            "deterministic reversal identity collision is refused");
         Assert
           (Read_Exact (Actual) = Before,
            "identity collision refusal leaves authority unchanged");
      end;

      --  Canonical Relation evidence is not skipped merely because it is
      --  unrelated to the selected target.  Until that family is represented
      --  by this bridge, the complete Actual image remains fail-closed.
      Reset_Root
        (Actual_Text =>
           "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
           & "TX" & HT & "record-1" & HT & "2026-09-20"
           & HT & "NODESC" & NL
           & "KEYED-EFFECT" & HT & "source-key" & HT
           & "cash" & HT & "jpy" & HT & "-120" & NL
           & "EFFECT" & HT & "food" & HT & "jpy" & HT & "120" & NL
           & "RELATION" & HT & "relation-1" & HT & "SOURCE" & HT
           & "source-key" & HT & "HOUSEHOLD" & HT & "OTHER:merchant"
           & HT & "120" & NL
           & "ENDTX" & NL);
      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Reversal
             (Root,
              (Token => Make_Token ("record-1")),
              (Year => 2026, Month => 9, Day => 22));
      begin
         Assert
           (not Rejected.Success,
            "unqualified canonical Relation evidence is not ignored");
         Assert
           (Read_Exact (Actual) = Before,
            "unsupported evidence refusal leaves authority unchanged");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Actual_Reversal_Writer;
