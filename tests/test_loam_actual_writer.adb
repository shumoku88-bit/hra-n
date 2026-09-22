with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Writer; use HRA_N.Storage.Loam_Actual_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Actual_Writer is

   package US renames Ada.Strings.Unbounded;

   Root   : constant String := "/tmp/hra_n_loam_actual_writer";
   Actual : constant String := Root & "/actual.loam";
   Policy : constant String := Root & "/locus-admission.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "fixture publishes atomically");
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

   procedure Run is
      Effects : Effect_List;
   begin
      Reset_Root;

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

      Effects.Count := 2;
      Effects.Values (1) :=
        (Key     => Retained_Effect_Key
           ((Token => Make_Token ("collector-left"))),
         Locus   => (Token => Make_Token ("cash")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => -250));
      Effects.Values (2) :=
        (Key     => Retained_Effect_Key
           ((Token => Make_Token ("collector-right"))),
         Locus   => (Token => Make_Token ("food")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => 250));

      declare
         Published : constant Publish_Result :=
           Publish_Movement
             (Root,
              (Year => 2026, Month => 9, Day => 22),
              Make_Description ("groceries"),
              Effects);
      begin
         Assert (Published.Success, "canonical Movement publication succeeds");
         Assert
           (Published.Success
            and then Equal_Token
              (Published.Event_Id, Make_Token ("record-2")),
            "writer follows Loam first-unused record-N identity allocation");
      end;

      declare
         Image : constant Loam_Actual_Result := Read_Loam_Actual_File (Actual);
      begin
         Assert (Image.Success, "published complete Actual generation re-admits");
         if Image.Success then
            Assert_Equal_Int
              (2, Long_Long_Integer (Image.Events.Length),
               "publication preserves prior Event and adds exactly one Event");
            declare
               Added : constant Event := Image.Events.Element (2);
               Desc  : Description_Text;
               Has_Desc : Boolean;
            begin
               Assert
                 (Equal_Token
                    (HRA_N.Core.Event.Id (Added).Token,
                     Make_Token ("record-2")),
                  "added Event has allocated canonical identity");
               Assert
                 (not Effect_At (Added, 1).Key.Present
                  and then not Effect_At (Added, 2).Key.Present,
                  "collector-local Effect keys are erased without relation evidence");
               Assert
                 (Is_Balanced_Single_Measure
                    (Added, (Token => Make_Token ("jpy"))),
                  "published Event retains single-Measure conservation");
               Find_Description
                 (Image.Descriptions,
                  HRA_N.Core.Event.Id (Added),
                  Desc,
                  Has_Desc);
               Assert
                 (Has_Desc
                  and then Equal_Description
                    (Desc, Make_Description ("groceries")),
                  "published description re-admits from canonical bytes");
            end;
         end if;
      end;

      Assert
        (not Ada.Directories.Exists (Actual & ".loam-stage"),
         "successful authority switch consumes sibling stage");
      Assert
        (Ada.Directories.Exists (Actual & ".loam-writer-lock"),
         "writer uses persistent Loam-compatible sibling ownership anchor");

      declare
         Before : constant String := Read_Exact (Actual);
         Rejected_Effects : Effect_List := Effects;
         Rejected : Publish_Result;
      begin
         Rejected_Effects.Values (2).Locus :=
           (Token => Make_Token ("unapproved"));
         Rejected :=
           Publish_Movement
             (Root,
              (Year => 2026, Month => 9, Day => 22),
              Make_Description ("must refuse"),
              Rejected_Effects);
         Assert
           (not Rejected.Success,
            "unapproved Locus fails closed");
         Assert
           (Read_Exact (Actual) = Before,
            "policy rejection leaves canonical Actual bytes untouched");
      end;

      declare
         Before : constant String := Read_Exact (Actual);
      begin
         Write_Atomically
           (Policy,
            "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
            & "LOCUS" & HT & "cash" & NL
            & "LOCUS" & HT & "cash" & NL);
         declare
            Rejected : constant Publish_Result :=
              Publish_Movement
                (Root,
                 (Year => 2026, Month => 9, Day => 22),
                 Make_Description ("must refuse"),
                 Effects);
         begin
            Assert
              (not Rejected.Success,
               "duplicate canonical policy identity fails closed");
            Assert
              (Read_Exact (Actual) = Before,
               "malformed policy leaves canonical Actual bytes untouched");
         end;
      end;

      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);
      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "broken" & HT & "2026-09-22" & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-1" & NL);

      declare
         Before : constant String := Read_Exact (Actual);
         Rejected : constant Publish_Result :=
           Publish_Movement
             (Root,
              (Year => 2026, Month => 9, Day => 22),
              Make_Description ("must refuse"),
              Effects);
      begin
         Assert
           (not Rejected.Success,
            "unadmitted existing Actual fails closed");
         Assert
           (Read_Exact (Actual) = Before,
            "existing-authority admission failure leaves bytes untouched");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Actual_Writer;
