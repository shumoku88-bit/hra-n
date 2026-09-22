-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata;
use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Locus_Admission_Reader;

package body HRA_N.Storage.Loam_Actual_Writer is

   package US renames Ada.Strings.Unbounded;
   package Actual_Reader renames HRA_N.Storage.Loam_Actual_Reader;
   package Locus_Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;

   function Valid_Token (Value : Token_Text) return Boolean is
   begin
      if Value.Length = 0 then
         return False;
      end if;
      for I in 1 .. Value.Length loop
         if Value.Value (I) in ASCII.HT | ASCII.LF | ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Token;

   function Valid_Description (Value : Description_Text) return Boolean is
   begin
      for I in 1 .. Value.Length loop
         if Value.Value (I) in ASCII.LF | ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Description;

   function Canonicalize_Effects (Raw : Effect_List) return Effect_List is
      Result : Effect_List := Raw;
   begin
      for I in 1 .. Result.Count loop
         Result.Values (I).Key := No_Effect_Key;
      end loop;
      return Result;
   end Canonicalize_Effects;

   function Event_Id_In_Use
     (Image     : Actual_Reader.Loam_Actual_Result;
      Candidate : String) return Boolean
   is
      Key : constant Token_Text := Make_Token (Candidate);
   begin
      for Item of Image.Events loop
         if Equal_Token (HRA_N.Core.Event.Id (Item).Token, Key) then
            return True;
         end if;
      end loop;
      return False;
   end Event_Id_In_Use;

   function Fresh_Numbered_Id
     (Image  : Actual_Reader.Loam_Actual_Result;
      Prefix : String) return Token_Text
   is
      Index : Positive := 1;
   begin
      loop
         declare
            Number    : constant String := Trim (Positive'Image (Index), Both);
            Candidate : constant String := Prefix & Number;
         begin
            if not Event_Id_In_Use (Image, Candidate) then
               return Make_Token (Candidate);
            end if;
         end;
         Index := Index + 1;
      end loop;
   end Fresh_Numbered_Id;

   function Fresh_Record_Id
     (Image : Actual_Reader.Loam_Actual_Result) return Token_Text is
     (Fresh_Numbered_Id (Image, "record-"));

   function Fresh_Replacement_Id
     (Image : Actual_Reader.Loam_Actual_Result) return Token_Text is
     (Fresh_Numbered_Id (Image, "replacement-"));

   function Encode_Event_Block
     (Event_Id     : Token_Text;
      Valid_On     : Date_Type;
      Description  : Description_Text;
      Effects      : Effect_List) return String
   is
      Block : US.Unbounded_String;
      HT    : constant String := [1 => ASCII.HT];
      NL    : constant String := [1 => ASCII.LF];
      Id    : constant String := Event_Id.Value (1 .. Event_Id.Length);
      Date  : constant String := Format_Iso_Date (Valid_On);
   begin
      if Description.Length = 0 then
         US.Append
           (Block, "TX" & HT & Id & HT & Date & HT & "NODESC" & NL);
      else
         US.Append
           (Block,
            "TX" & HT & Id & HT & Date & HT & "DESC" & HT
            & HRA_N.Core.Description.To_String (Description) & NL);
      end if;

      for I in 1 .. Effects.Count loop
         declare
            Item    : constant Effect := Effects.Values (I);
            Locus   : constant String :=
              Item.Locus.Token.Value (1 .. Item.Locus.Token.Length);
            Measure : constant String :=
              Item.Measure.Token.Value (1 .. Item.Measure.Token.Length);
            Amount  : constant String :=
              Trim (Quanta_Type'Image (Item.Amount.Quanta), Both);
         begin
            US.Append
              (Block,
               "EFFECT" & HT & Locus & HT & Measure & HT & Amount & NL);
         end;
      end loop;

      US.Append (Block, "ENDTX" & NL);
      return US.To_String (Block);
   end Encode_Event_Block;

   function Encode_Correction_Block
     (Event_Id     : Token_Text;
      Target       : HRA_N.Core.Types.Event_Id;
      Valid_On     : Date_Type;
      Description  : Description_Text;
      Effects      : Effect_List) return String
   is
      Block : US.Unbounded_String;
      HT    : constant String := [1 => ASCII.HT];
      NL    : constant String := [1 => ASCII.LF];
      Id    : constant String := Event_Id.Value (1 .. Event_Id.Length);
      Target_Text : constant String :=
        Target.Token.Value (1 .. Target.Token.Length);
      Date  : constant String := Format_Iso_Date (Valid_On);
   begin
      if Description.Length = 0 then
         US.Append
           (Block, "TX" & HT & Id & HT & Date & HT & "NODESC" & NL);
      else
         US.Append
           (Block,
            "TX" & HT & Id & HT & Date & HT & "DESC" & HT
            & HRA_N.Core.Description.To_String (Description) & NL);
      end if;

      --  Match Loam normalized Actual encoder order: correction metadata is
      --  represented before the replacement Event's Effects.
      US.Append (Block, "REPLACES" & HT & Target_Text & NL);

      for I in 1 .. Effects.Count loop
         declare
            Item    : constant Effect := Effects.Values (I);
            Locus   : constant String :=
              Item.Locus.Token.Value (1 .. Item.Locus.Token.Length);
            Measure : constant String :=
              Item.Measure.Token.Value (1 .. Item.Measure.Token.Length);
            Amount  : constant String :=
              Trim (Quanta_Type'Image (Item.Amount.Quanta), Both);
         begin
            US.Append
              (Block,
               "EFFECT" & HT & Locus & HT & Measure & HT & Amount & NL);
         end;
      end loop;

      US.Append (Block, "ENDTX" & NL);
      return US.To_String (Block);
   end Encode_Correction_Block;

   function Candidate_Corresponds
     (Image             : Actual_Reader.Loam_Actual_Result;
      Prior_Event_Count : Natural;
      Event_Id          : Token_Text;
      Valid_On          : Date_Type;
      Description       : Description_Text;
      Effects           : Effect_List) return Boolean
   is
      Date       : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_Date   : Boolean := False;
      Desc       : Description_Text :=
        (Length => 0, Value => [others => ' ']);
      Has_Desc   : Boolean := False;
   begin
      if not Image.Success
        or else Natural (Image.Events.Length) /= Prior_Event_Count + 1
      then
         return False;
      end if;

      declare
         Item : constant Event :=
           Image.Events.Element (Positive (Prior_Event_Count + 1));
      begin
         if not Equal_Token (HRA_N.Core.Event.Id (Item).Token, Event_Id)
           or else HRA_N.Core.Event.Effects (Item) /= Effects
         then
            return False;
         end if;
      end;

      Find_Occurrence_Date
        (Image.Validities, (Token => Event_Id), Date, Has_Date);
      if not Has_Date or else not Equal_Date (Date, Valid_On) then
         return False;
      end if;

      Find_Description
        (Image.Descriptions, (Token => Event_Id), Desc, Has_Desc);
      if Description.Length = 0 then
         return not Has_Desc;
      else
         return Has_Desc and then Equal_Description (Desc, Description);
      end if;
   end Candidate_Corresponds;

   procedure Find_Event_By_Id
     (Image  : Actual_Reader.Loam_Actual_Result;
      Key    : HRA_N.Core.Types.Event_Id;
      Item   : out Event;
      Found  : out Boolean)
   is
   begin
      Item :=
        Make_Event
          ((Token => (Length => 0, Value => [others => ' '])),
           (Count => 0, Values => [others => Empty_Effect]));
      Found := False;
      for Candidate of Image.Events loop
         if Equal_Token (HRA_N.Core.Event.Id (Candidate).Token, Key.Token) then
            Item := Candidate;
            Found := True;
            return;
         end if;
      end loop;
   end Find_Event_By_Id;

   procedure Practical_Measure
     (Item    : in Event;
      Measure : out Measure_Id;
      Valid   : out Boolean)
   is
   begin
      Measure := (Token => (Length => 0, Value => [others => ' ']));
      Valid := False;
      if Effect_Count (Item) < 2 then
         return;
      end if;

      Measure := Effect_At (Item, 1).Measure;
      for I in 1 .. Effect_Count (Item) loop
         if Effect_At (Item, Effect_Index_Type (I)).Amount.Quanta = 0
           or else not Equal_Token
             (Effect_At (Item, Effect_Index_Type (I)).Measure.Token,
              Measure.Token)
         then
            return;
         end if;
      end loop;

      Valid := Is_Balanced_Single_Measure (Item, Measure);
   end Practical_Measure;

   function Target_Is_Current
     (Image  : Actual_Reader.Loam_Actual_Result;
      Target : HRA_N.Core.Types.Event_Id) return Boolean
   is
      Successor : HRA_N.Core.Types.Event_Id;
      Found     : Boolean;
   begin
      Find_Successor (Image.Metadata, Target, Successor, Found);
      return not Found;
   end Target_Is_Current;

   function Target_Participates_In_Reversal
     (Image  : Actual_Reader.Loam_Actual_Result;
      Target : HRA_N.Core.Types.Event_Id) return Boolean
   is
      Meta      : Transaction_Metadata_Entry;
      Has_Meta  : Boolean;
      Reverser  : HRA_N.Core.Types.Event_Id;
      Has_Rev   : Boolean;
   begin
      Find_Metadata (Image.Metadata, Target, Meta, Has_Meta);
      if Has_Meta and then Meta.Reverses.Present then
         return True;
      end if;
      Find_Reverser (Image.Metadata, Target, Reverser, Has_Rev);
      return Has_Rev;
   end Target_Participates_In_Reversal;

   function Correction_Candidate_Corresponds
     (Image             : Actual_Reader.Loam_Actual_Result;
      Prior_Event_Count : Natural;
      Replacement_Id    : Token_Text;
      Target            : HRA_N.Core.Types.Event_Id;
      Valid_On          : Date_Type;
      Description       : Description_Text;
      Effects           : Effect_List) return Boolean
   is
      Date       : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_Date   : Boolean := False;
      Desc       : Description_Text :=
        (Length => 0, Value => [others => ' ']);
      Has_Desc   : Boolean := False;
      Meta       : Transaction_Metadata_Entry;
      Has_Meta   : Boolean := False;
      Successor  : HRA_N.Core.Types.Event_Id;
      Has_Succ   : Boolean := False;
   begin
      if not Image.Success
        or else Natural (Image.Events.Length) /= Prior_Event_Count + 1
      then
         return False;
      end if;

      declare
         Added : constant Event :=
           Image.Events.Element (Positive (Prior_Event_Count + 1));
      begin
         if not Equal_Token
           (HRA_N.Core.Event.Id (Added).Token, Replacement_Id)
           or else HRA_N.Core.Event.Effects (Added) /= Effects
         then
            return False;
         end if;
      end;

      Find_Occurrence_Date
        (Image.Validities, (Token => Replacement_Id), Date, Has_Date);
      if not Has_Date or else not Equal_Date (Date, Valid_On) then
         return False;
      end if;

      Find_Description
        (Image.Descriptions, (Token => Replacement_Id), Desc, Has_Desc);
      if Description.Length = 0 then
         if Has_Desc then
            return False;
         end if;
      elsif not Has_Desc
        or else not Equal_Description (Desc, Description)
      then
         return False;
      end if;

      Find_Metadata
        (Image.Metadata, (Token => Replacement_Id), Meta, Has_Meta);
      if not Has_Meta
        or else not Meta.Replaces.Present
        or else not Equal_Token (Meta.Replaces.Value.Token, Target.Token)
        or else Meta.Reverses.Present
      then
         return False;
      end if;

      Find_Successor (Image.Metadata, Target, Successor, Has_Succ);
      return Has_Succ
        and then Equal_Token (Successor.Token, Replacement_Id);
   end Correction_Candidate_Corresponds;

   function Publish_Movement
     (Root_Path   : String;
      Valid_On    : Date_Type;
      Description : Description_Text;
      Effects     : Effect_List) return Publish_Result
   is
      Result : Publish_Result;
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
      Policy_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
      Stage_Path : constant String := Actual_Path & ".loam-stage";
      Lock_Path  : constant String := Actual_Path & ".loam-writer-lock";
      Lock       : HRA_N.Storage.File_Lock.Lock_Handle;

      procedure Set_Error (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Reason := [others => ' '];
         Result.Error_Len := Len;
         if Len > 0 then
            Result.Error_Reason (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
      end Set_Error;

      function Fail (Message : String) return Publish_Result is
      begin
         Set_Error (Message);
         return Result;
      end Fail;

      procedure Release is
      begin
         HRA_N.Storage.File_Lock.Release (Lock);
      exception
         when others =>
            null;
      end Release;

      procedure Remove_Stage is
      begin
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
      exception
         when others =>
            null;
      end Remove_Stage;

   begin
      if Root_Path'Length = 0 then
         return Fail ("LOAM data root must not be empty");
      elsif not Is_Valid_Date
        (Valid_On.Year, Valid_On.Month, Valid_On.Day)
      then
         return Fail ("movement occurrence date is invalid");
      elsif not Valid_Description (Description) then
         return Fail ("movement description is not canonically encodable");
      elsif Effects.Count < 2 then
         return Fail ("movement needs at least two Effects");
      end if;

      declare
         Canonical : constant Effect_List := Canonicalize_Effects (Effects);
         Measure   : constant Measure_Id := Canonical.Values (1).Measure;
         Sum       : Long_Long_Integer := 0;
         Positive  : Long_Long_Integer := 0;
      begin
         for I in 1 .. Canonical.Count loop
            if not Valid_Token (Canonical.Values (I).Locus.Token)
              or else not Valid_Token (Canonical.Values (I).Measure.Token)
              or else Canonical.Values (I).Amount.Quanta = 0
            then
               return Fail
                 ("movement requires valid tokens and nonzero quantities");
            elsif not Equal_Token
              (Canonical.Values (I).Measure.Token, Measure.Token)
            then
               return Fail ("movement must use one Measure");
            end if;

            Sum := Sum + Long_Long_Integer
              (Canonical.Values (I).Amount.Quanta);
            if Canonical.Values (I).Amount.Quanta > 0 then
               Positive := Positive + Long_Long_Integer
                 (Canonical.Values (I).Amount.Quanta);
            end if;
         end loop;

         if Sum /= 0 or else Positive <= 0 then
            return Fail ("movement must be one balanced nonzero Measure");
         end if;

         if not HRA_N.Storage.File_Lock.Acquire (Lock_Path, Lock) then
            return Fail ("cannot acquire LOAM Actual writer ownership");
         end if;

         declare
            Existing : constant HRA_N.Storage.Exact_File.Read_Result :=
              HRA_N.Storage.Exact_File.Read_All (Actual_Path);
         begin
            if not Existing.Success then
               Release;
               return Fail ("cannot read current actual.loam authority");
            end if;

            declare
               Existing_Text : constant String :=
                 US.To_String (Existing.Content);
               Current : constant Actual_Reader.Loam_Actual_Result :=
                 Actual_Reader.Read_Loam_Actual_Content (Existing_Text);
               Policy : constant Locus_Reader.Read_Result :=
                 Locus_Reader.Read_File (Policy_Path);
            begin
               if not Current.Success then
                  Release;
                  return Fail
                    ("current actual.loam is malformed, unsupported, or over capacity");
               elsif not Policy.Success then
                  Release;
                  return Fail
                    ("current locus-admission.loam is malformed or unsupported");
               elsif not Admits_Effects (Policy.Vocabulary, Canonical) then
                  Release;
                  return Fail
                    ("movement uses a Locus not approved for new publication");
               elsif Natural (Current.Events.Length) =
                 Actual_Reader.Max_Admitted_Actual_Events
               then
                  Release;
                  return Fail
                    ("HRA-N Actual writer working-set capacity exceeded");
               end if;

               declare
                  New_Id : constant Token_Text := Fresh_Record_Id (Current);
                  Block  : constant String :=
                    Encode_Event_Block
                      (New_Id, Valid_On, Description, Canonical);
                  Candidate : constant String := Existing_Text & Block;
                  Admitted : constant Actual_Reader.Loam_Actual_Result :=
                    Actual_Reader.Read_Loam_Actual_Content (Candidate);
                  Error     : String (1 .. 192) := [others => ' '];
                  Error_Len : Natural := 0;
               begin
                  if not Candidate_Corresponds
                    (Admitted,
                     Natural (Current.Events.Length),
                     New_Id,
                     Valid_On,
                     Description,
                     Canonical)
                  then
                     Release;
                     return Fail
                       ("candidate Actual generation failed semantic correspondence");
                  end if;

                  Remove_Stage;
                  if not HRA_N.Storage.Atomic_Writer.Write_Staging_File_Durably
                    (Stage_Path, Candidate, Error, Error_Len)
                  then
                     Release;
                     return Fail
                       ("cannot durably stage canonical Actual candidate");
                  end if;

                  declare
                     Staged : constant HRA_N.Storage.Exact_File.Read_Result :=
                       HRA_N.Storage.Exact_File.Read_All (Stage_Path);
                  begin
                     if not Staged.Success
                       or else US.To_String (Staged.Content) /= Candidate
                     then
                        Remove_Stage;
                        Release;
                        return Fail
                          ("staged Actual bytes do not match candidate generation");
                     end if;

                     declare
                        Staged_Image : constant Actual_Reader.Loam_Actual_Result :=
                          Actual_Reader.Read_Loam_Actual_Content
                            (US.To_String (Staged.Content));
                     begin
                        if not Candidate_Corresponds
                          (Staged_Image,
                           Natural (Current.Events.Length),
                           New_Id,
                           Valid_On,
                           Description,
                           Canonical)
                        then
                           Remove_Stage;
                           Release;
                           return Fail
                             ("staged Actual generation failed semantic admission");
                        end if;
                     end;
                  end;

                  if not HRA_N.Storage.Atomic_Writer.Publish_Staged_File_Atomically
                    (Stage_Path, Actual_Path, Error, Error_Len)
                  then
                     Release;
                     return Fail
                       ("failed to switch canonical Actual authority");
                  end if;

                  Result.Success := True;
                  Result.Event_Id := New_Id;
                  Release;
                  return Result;
               end;
            end;
         end;
      end;

   exception
      when others =>
         Remove_Stage;
         Release;
         return Fail ("unexpected LOAM Actual writer failure");
   end Publish_Movement;

   function Publish_Correction
     (Root_Path   : String;
      Target      : HRA_N.Core.Types.Event_Id;
      Description : Description_Text;
      Effects     : Effect_List) return Publish_Result
   is
      Result : Publish_Result;
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
      Policy_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
      Stage_Path : constant String := Actual_Path & ".loam-stage";
      Lock_Path  : constant String := Actual_Path & ".loam-writer-lock";
      Lock       : HRA_N.Storage.File_Lock.Lock_Handle;

      procedure Set_Error (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Reason := [others => ' '];
         Result.Error_Len := Len;
         if Len > 0 then
            Result.Error_Reason (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
      end Set_Error;

      function Fail (Message : String) return Publish_Result is
      begin
         Set_Error (Message);
         return Result;
      end Fail;

      procedure Release is
      begin
         HRA_N.Storage.File_Lock.Release (Lock);
      exception
         when others =>
            null;
      end Release;

      procedure Remove_Stage is
      begin
         if Ada.Directories.Exists (Stage_Path) then
            Ada.Directories.Delete_File (Stage_Path);
         end if;
      exception
         when others =>
            null;
      end Remove_Stage;

   begin
      if Root_Path'Length = 0 then
         return Fail ("LOAM data root must not be empty");
      elsif not Valid_Token (Target.Token) then
         return Fail ("correction target identity is invalid");
      elsif not Valid_Description (Description) then
         return Fail ("correction description is not canonically encodable");
      elsif Effects.Count < 2 then
         return Fail ("correction replacement needs at least two Effects");
      end if;

      declare
         Canonical : constant Effect_List := Canonicalize_Effects (Effects);
         Measure   : constant Measure_Id := Canonical.Values (1).Measure;
         Sum       : Long_Long_Integer := 0;
         Positive  : Long_Long_Integer := 0;
      begin
         for I in 1 .. Canonical.Count loop
            if not Valid_Token (Canonical.Values (I).Locus.Token)
              or else not Valid_Token (Canonical.Values (I).Measure.Token)
              or else Canonical.Values (I).Amount.Quanta = 0
            then
               return Fail
                 ("correction replacement requires valid tokens and nonzero quantities");
            elsif not Equal_Token
              (Canonical.Values (I).Measure.Token, Measure.Token)
            then
               return Fail ("correction replacement must use one Measure");
            end if;

            Sum := Sum + Long_Long_Integer
              (Canonical.Values (I).Amount.Quanta);
            if Canonical.Values (I).Amount.Quanta > 0 then
               Positive := Positive + Long_Long_Integer
                 (Canonical.Values (I).Amount.Quanta);
            end if;
         end loop;

         if Sum /= 0 or else Positive <= 0 then
            return Fail
              ("correction replacement must be one balanced nonzero Measure");
         end if;

         if not HRA_N.Storage.File_Lock.Acquire (Lock_Path, Lock) then
            return Fail ("cannot acquire LOAM Actual writer ownership");
         end if;

         declare
            Existing : constant HRA_N.Storage.Exact_File.Read_Result :=
              HRA_N.Storage.Exact_File.Read_All (Actual_Path);
         begin
            if not Existing.Success then
               Release;
               return Fail ("cannot read current actual.loam authority");
            end if;

            declare
               Existing_Text : constant String := US.To_String (Existing.Content);
               Current : constant Actual_Reader.Loam_Actual_Result :=
                 Actual_Reader.Read_Loam_Actual_Content (Existing_Text);
               Policy : constant Locus_Reader.Read_Result :=
                 Locus_Reader.Read_File (Policy_Path);
               Target_Event : Event;
               Have_Target  : Boolean;
               Target_Measure : Measure_Id;
               Target_Practical : Boolean;
               Target_Date : Date_Type := (Year => 2026, Month => 1, Day => 1);
               Have_Date   : Boolean := False;
            begin
               if not Current.Success then
                  Release;
                  return Fail
                    ("current actual.loam is malformed, unsupported, or over capacity");
               elsif not Policy.Success then
                  Release;
                  return Fail
                    ("current locus-admission.loam is malformed or unsupported");
               elsif not Admits_Effects (Policy.Vocabulary, Canonical) then
                  Release;
                  return Fail
                    ("correction replacement uses a Locus not approved for new publication");
               elsif Natural (Current.Events.Length) =
                 Actual_Reader.Max_Admitted_Actual_Events
               then
                  Release;
                  return Fail
                    ("HRA-N Actual writer working-set capacity exceeded");
               end if;

               Find_Event_By_Id (Current, Target, Target_Event, Have_Target);
               if not Have_Target then
                  Release;
                  return Fail ("selected correction target is not retained");
               elsif not Target_Is_Current (Current, Target) then
                  Release;
                  return Fail ("selected Actual is no longer current");
               elsif Target_Participates_In_Reversal (Current, Target) then
                  Release;
                  return Fail
                    ("correction of an Actual participating in Reversal evidence is not qualified");
               end if;

               Practical_Measure
                 (Target_Event, Target_Measure, Target_Practical);
               if not Target_Practical then
                  Release;
                  return Fail
                    ("selected Actual is outside the practical balanced single-Measure correction entrance");
               elsif not Equal_Token (Target_Measure.Token, Measure.Token) then
                  Release;
                  return Fail
                    ("correction must preserve the target Measure");
               end if;

               Find_Occurrence_Date
                 (Current.Validities, Target, Target_Date, Have_Date);
               if not Have_Date then
                  Release;
                  return Fail
                    ("selected Actual has no current occurrence date");
               end if;

               declare
                  Replacement_Id : constant Token_Text :=
                    Fresh_Replacement_Id (Current);
                  Block : constant String :=
                    Encode_Correction_Block
                      (Replacement_Id,
                       Target,
                       Target_Date,
                       Description,
                       Canonical);
                  Candidate : constant String := Existing_Text & Block;
                  Admitted : constant Actual_Reader.Loam_Actual_Result :=
                    Actual_Reader.Read_Loam_Actual_Content (Candidate);
                  Error     : String (1 .. 192) := [others => ' '];
                  Error_Len : Natural := 0;
               begin
                  if not Correction_Candidate_Corresponds
                    (Admitted,
                     Natural (Current.Events.Length),
                     Replacement_Id,
                     Target,
                     Target_Date,
                     Description,
                     Canonical)
                  then
                     Release;
                     return Fail
                       ("candidate correction generation failed semantic correspondence");
                  end if;

                  Remove_Stage;
                  if not HRA_N.Storage.Atomic_Writer.Write_Staging_File_Durably
                    (Stage_Path, Candidate, Error, Error_Len)
                  then
                     Release;
                     return Fail
                       ("cannot durably stage canonical correction candidate");
                  end if;

                  declare
                     Staged : constant HRA_N.Storage.Exact_File.Read_Result :=
                       HRA_N.Storage.Exact_File.Read_All (Stage_Path);
                  begin
                     if not Staged.Success
                       or else US.To_String (Staged.Content) /= Candidate
                     then
                        Remove_Stage;
                        Release;
                        return Fail
                          ("staged correction bytes do not match candidate generation");
                     end if;

                     declare
                        Staged_Image : constant Actual_Reader.Loam_Actual_Result :=
                          Actual_Reader.Read_Loam_Actual_Content
                            (US.To_String (Staged.Content));
                     begin
                        if not Correction_Candidate_Corresponds
                          (Staged_Image,
                           Natural (Current.Events.Length),
                           Replacement_Id,
                           Target,
                           Target_Date,
                           Description,
                           Canonical)
                        then
                           Remove_Stage;
                           Release;
                           return Fail
                             ("staged correction generation failed semantic admission");
                        end if;
                     end;
                  end;

                  if not HRA_N.Storage.Atomic_Writer.Publish_Staged_File_Atomically
                    (Stage_Path, Actual_Path, Error, Error_Len)
                  then
                     Release;
                     return Fail
                       ("failed to switch canonical Actual correction authority");
                  end if;

                  Result.Success := True;
                  Result.Event_Id := Replacement_Id;
                  Release;
                  return Result;
               end;
            end;
         end;
      end;

   exception
      when others =>
         Remove_Stage;
         Release;
         return Fail ("unexpected LOAM Actual correction writer failure");
   end Publish_Correction;

end HRA_N.Storage.Loam_Actual_Writer;
