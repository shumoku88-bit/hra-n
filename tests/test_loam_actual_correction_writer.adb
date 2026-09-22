with Ada.Directories;
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

package body Test_Loam_Actual_Correction_Writer is

   package US renames Ada.Strings.Unbounded;

   Root   : constant String := "/tmp/hra_n_loam_actual_correction_writer";
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
         "correction fixture publishes atomically");
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
      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);
   end Reset_Root;

   function Replacement_Effects
     (Amount  : Quanta_Type;
      Measure : String := "jpy";
      To_Name : String := "food") return Effect_List
   is
      Items : Effect_List;
   begin
      Items.Count := 2;
      Items.Values (1) :=
        (Key     => Retained_Effect_Key
           ((Token => Make_Token ("collector-left"))),
         Locus   => (Token => Make_Token ("cash")),
         Measure => (Token => Make_Token (Measure)),
         Amount  => (Quanta => -Amount));
      Items.Values (2) :=
        (Key     => Retained_Effect_Key
           ((Token => Make_Token ("collector-right"))),
         Locus   => (Token => Make_Token (To_Name)),
         Measure => (Token => Make_Token (Measure)),
         Amount  => (Quanta => Amount));
      return Items;
   end Replacement_Effects;

   procedure Run is
   begin
      Reset_Root;
      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "record-1" & HT & "2026-09-20"
         & HT & "DESC" & HT & "old description" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-10" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "10" & NL
         & "ENDTX" & NL);

      declare
         Published : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("record-1")),
              Make_Description ("corrected"),
              Replacement_Effects (15));
      begin
         Assert (Published.Success, "canonical correction publication succeeds");
         Assert
           (Published.Success
            and then Equal_Token
              (Published.Event_Id, Make_Token ("replacement-1")),
            "correction follows Loam first-unused replacement-N identity");
      end;

      declare
         Image : constant Loam_Actual_Result := Read_Loam_Actual_File (Actual);
         Successor : Event_Id;
         Has_Successor : Boolean;
         Replacement_Date : Date_Type;
         Has_Date : Boolean;
         Replacement_Desc : Description_Text;
         Has_Desc : Boolean;
      begin
         Assert (Image.Success, "corrected canonical generation re-admits");
         Assert_Equal_Int
           (2, Long_Long_Integer (Image.Events.Length),
            "correction retains original Event and appends one replacement");
         Find_Successor
           (Image.Metadata,
            (Token => Make_Token ("record-1")),
            Successor,
            Has_Successor);
         Assert
           (Has_Successor
            and then Equal_Token
              (Successor.Token, Make_Token ("replacement-1")),
            "replacement topology explicitly links replacement to target");
         Find_Occurrence_Date
           (Image.Validities,
            (Token => Make_Token ("replacement-1")),
            Replacement_Date,
            Has_Date);
         Assert
           (Has_Date
            and then Equal_Date
              (Replacement_Date, (Year => 2026, Month => 9, Day => 20)),
            "replacement inherits target occurrence date");
         Find_Description
           (Image.Descriptions,
            (Token => Make_Token ("replacement-1")),
            Replacement_Desc,
            Has_Desc);
         Assert
           (Has_Desc
            and then Equal_Description
              (Replacement_Desc, Make_Description ("corrected")),
            "replacement carries explicitly supplied description");
         declare
            Added : constant Event := Image.Events.Element (2);
         begin
            Assert
              (not Effect_At (Added, 1).Key.Present
               and then not Effect_At (Added, 2).Key.Present,
               "correction canonicalizes collector-local Effect keys away");
         end;
      end;

      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("record-1")),
              Make_Description ("second opinion"),
              Replacement_Effects (20));
      begin
         Assert
           (not Rejected.Success,
            "already replaced target is no longer current");
         Assert
           (Read_Exact (Actual) = Before,
            "non-current target rejection leaves authority unchanged");
      end;

      declare
         Chained : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("replacement-1")),
              (Length => 0, Value => [others => ' ']),
              Replacement_Effects (25));
      begin
         Assert
           (Chained.Success
            and then Equal_Token
              (Chained.Event_Id, Make_Token ("replacement-2")),
            "current replacement may itself be corrected");
      end;

      declare
         Image : constant Loam_Actual_Result := Read_Loam_Actual_File (Actual);
         Desc  : Description_Text;
         Has_Desc : Boolean;
      begin
         Assert (Image.Success, "correction chain remains admitted");
         Assert_Equal_Int
           (3, Long_Long_Integer (Image.Events.Length),
            "correction chain appends without deleting history");
         Find_Description
           (Image.Descriptions,
            (Token => Make_Token ("replacement-2")),
            Desc,
            Has_Desc);
         Assert
           (not Has_Desc,
            "empty correction description does not copy prior description");
      end;

      declare
         Before : constant String := Read_Exact (Actual);
         Cross_Measure : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("replacement-2")),
              Make_Description ("wrong measure"),
              Replacement_Effects (30, "usd"));
      begin
         Assert
           (not Cross_Measure.Success,
            "cross-Measure correction is rejected");
         Assert
           (Read_Exact (Actual) = Before,
            "cross-Measure rejection leaves authority unchanged");
      end;

      declare
         Before : constant String := Read_Exact (Actual);
         Missing : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("missing")),
              Make_Description ("missing"),
              Replacement_Effects (30));
      begin
         Assert (not Missing.Success, "missing correction target is rejected");
         Assert
           (Read_Exact (Actual) = Before,
            "missing target rejection leaves authority unchanged");
      end;

      declare
         Before : constant String := Read_Exact (Actual);
         Unapproved : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("replacement-2")),
              Make_Description ("bad locus"),
              Replacement_Effects (30, "jpy", "unknown"));
      begin
         Assert (not Unapproved.Success, "unapproved replacement Locus is rejected");
         Assert
           (Read_Exact (Actual) = Before,
            "policy rejection leaves corrected authority unchanged");
      end;

      --  Reversal participation is outside the qualified correction entrance.
      Reset_Root;
      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "record-1" & HT & "2026-09-20" & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-10" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "10" & NL
         & "ENDTX" & NL
         & "TX" & HT & "reversal-1" & HT & "2026-09-20" & HT & "NODESC" & NL
         & "REVERSAL-OF" & HT & "record-1" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "10" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "-10" & NL
         & "ENDTX" & NL);

      declare
         Before : constant String := Read_Exact (Actual);
         Target_Side : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("record-1")),
              Make_Description ("not qualified"),
              Replacement_Effects (11));
         Reversal_Side : constant Publish_Result :=
           Publish_Correction
             (Root,
              (Token => Make_Token ("reversal-1")),
              Make_Description ("not qualified"),
              Replacement_Effects (11));
      begin
         Assert
           (not Target_Side.Success and then not Reversal_Side.Success,
            "either endpoint of reversal evidence is refused as correction target");
         Assert
           (Read_Exact (Actual) = Before,
            "reversal participation rejection leaves authority unchanged");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Actual_Correction_Writer;
