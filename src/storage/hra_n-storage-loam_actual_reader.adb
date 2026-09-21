-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Quantity;             use HRA_N.Core.Quantity;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;

package body HRA_N.Storage.Loam_Actual_Reader is

   Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";

   function Field_Count (Line : String) return Natural is
      Count : Natural := 1;
   begin
      if Line'Length = 0 then
         return 1;
      end if;
      for C of Line loop
         if C = ASCII.HT then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Field_Count;

   function Field (Line : String; Number : Positive) return String is
      Start   : Natural := Line'First;
      Current : Positive := 1;
   begin
      if Line'Length = 0 then
         return "";
      end if;

      for I in Line'Range loop
         if Line (I) = ASCII.HT then
            if Current = Number then
               if I = Start then
                  return "";
               else
                  return Line (Start .. I - 1);
               end if;
            end if;
            Current := Current + 1;
            Start := I + 1;
         end if;
      end loop;

      if Current = Number then
         if Start > Line'Last then
            return "";
         else
            return Line (Start .. Line'Last);
         end if;
      end if;
      return "";
   end Field;

   function Remainder_After
     (Line       : String;
      Delimiters : Positive) return String
   is
      Seen : Natural := 0;
   begin
      for I in Line'Range loop
         if Line (I) = ASCII.HT then
            Seen := Seen + 1;
            if Seen = Delimiters then
               if I = Line'Last then
                  return "";
               else
                  return Line (I + 1 .. Line'Last);
               end if;
            end if;
         end if;
      end loop;
      return "";
   end Remainder_After;

   function Valid_Token (S : String) return Boolean is
   begin
      if S'Length = 0 or else S'Length > Max_Token_Length then
         return False;
      end if;
      for C of S loop
         if C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Token;

   function Parse_Quanta
     (Text  : String;
      Value : out Quanta_Type) return Boolean
   is
      Start : Natural := Text'First;
   begin
      Value := 0;
      if Text'Length = 0 then
         return False;
      end if;

      if Text (Start) = '-' then
         if Text'Length = 1 then
            return False;
         end if;
         Start := Start + 1;
      end if;

      for I in Start .. Text'Last loop
         if Text (I) not in '0' .. '9' then
            return False;
         end if;
      end loop;

      declare
         Parsed : constant Long_Long_Integer := Long_Long_Integer'Value (Text);
      begin
         if Parsed < Long_Long_Integer (Quanta_Type'First)
           or else Parsed > Long_Long_Integer (Quanta_Type'Last)
         then
            return False;
         end if;
         Value := Quanta_Type (Parsed);
         return True;
      end;
   exception
      when others =>
         Value := 0;
         return False;
   end Parse_Quanta;

   Empty_Effects : constant Effect_List :=
     (Count => 0, Values => [others => Empty_Effect]);

   Empty_Event : constant Event :=
     Make_Event
       ((Token => (Length => 0, Value => [others => ' '])),
        Empty_Effects);

   procedure Find_Event
     (Events : in Event_Vectors.Vector;
      Ev_Id  : in Event_Id;
      Item   : out Event;
      Found  : out Boolean)
   is
   begin
      Item := Empty_Event;
      Found := False;
      for Ev of Events loop
         if Equal_Token (Id (Ev).Token, Ev_Id.Token) then
            Item := Ev;
            Found := True;
            return;
         end if;
      end loop;
   end Find_Event;

   function Event_Exists
     (Events : Event_Vectors.Vector;
      Ev_Id  : Event_Id) return Boolean
   is
      Item  : Event;
      Found : Boolean;
   begin
      Find_Event (Events, Ev_Id, Item, Found);
      return Found;
   end Event_Exists;

   function Exact_Physical_Inverse
     (Target   : Event;
      Reversal : Event) return Boolean
   is
      Matched : array (Effect_Index_Type) of Boolean := [others => False];
   begin
      if Effect_Count (Target) /= Effect_Count (Reversal) then
         return False;
      end if;

      for I in 1 .. Effect_Count (Target) loop
         declare
            T     : constant Effect := Effect_At (Target, Effect_Index_Type (I));
            Found : Boolean := False;
         begin
            for J in 1 .. Effect_Count (Reversal) loop
               if not Matched (Effect_Index_Type (J)) then
                  declare
                     R : constant Effect :=
                       Effect_At (Reversal, Effect_Index_Type (J));
                  begin
                     if Equal_Token (T.Locus.Token, R.Locus.Token)
                       and then Equal_Token (T.Measure.Token, R.Measure.Token)
                       and then R.Amount.Quanta = -T.Amount.Quanta
                     then
                        Matched (Effect_Index_Type (J)) := True;
                        Found := True;
                        exit;
                     end if;
                  end;
               end if;
            end loop;
            if not Found then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Exact_Physical_Inverse;

   function Read_Loam_Actual_File
     (Path : String) return Loam_Actual_Result
   is
      Result : Loam_Actual_Result;
      File   : Ada.Text_IO.File_Type;
      Exact  : constant HRA_N.Storage.Exact_File.Read_Result :=
        HRA_N.Storage.Exact_File.Read_All (Path);

      Validity_Entries    : Validity_Entry_List;
      Description_Entries : Description_Entry_List;
      Metadata_Entries    : Metadata_List;

      In_Tx             : Boolean := False;
      Current_Id        : Event_Id :=
        (Token => (Length => 0, Value => [others => ' ']));
      Current_Date      : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Current_Effects   : Effect_List;
      Current_Replaces  : Optional_Event_Id :=
        (Present => False,
         Value => (Token => (Length => 0, Value => [others => ' '])));
      Current_Reverses  : Optional_Event_Id :=
        (Present => False,
         Value => (Token => (Length => 0, Value => [others => ' '])));
      Has_Description   : Boolean := False;
      Current_Desc      : Description_Text :=
        (Length => 0, Value => [others => ' ']);
      Line_No           : Natural := 0;

      procedure Set_Error
        (At_Line : Natural;
         Message : String)
      is
         N : constant Natural := Natural'Min (Message'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Line := At_Line;
         Result.Error_Reason := [others => ' '];
         Result.Error_Len := N;
         if N > 0 then
            Result.Error_Reason (1 .. N) :=
              Message (Message'First .. Message'First + N - 1);
         end if;
      end Set_Error;

      function Fail
        (At_Line : Natural;
         Message : String) return Loam_Actual_Result
      is
      begin
         Set_Error (At_Line, Message);
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Result;
      end Fail;

      procedure Reset_Current is
      begin
         Current_Id :=
           (Token => (Length => 0, Value => [others => ' ']));
         Current_Date := (Year => 2026, Month => 1, Day => 1);
         Current_Effects := Empty_Effects;
         Current_Replaces :=
           (Present => False,
            Value => (Token => (Length => 0, Value => [others => ' '])));
         Current_Reverses :=
           (Present => False,
            Value => (Token => (Length => 0, Value => [others => ' '])));
         Has_Description := False;
         Current_Desc := (Length => 0, Value => [others => ' ']);
      end Reset_Current;

   begin
      if not Exact.Success then
         return Fail (0, "cannot read LOAM Actual file");
      end if;

      declare
         Bytes : constant String := To_String (Exact.Content);
      begin
         if Bytes'Length = 0 then
            return Fail (0, "LOAM Actual document is empty");
         elsif Bytes (Bytes'Last) /= ASCII.LF then
            return Fail (0, "LOAM Actual document must end with newline");
         end if;
      end;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      if Ada.Text_IO.End_Of_File (File) then
         return Fail (0, "LOAM Actual document is empty");
      end if;

      Line_No := 1;
      declare
         First_Line : constant String := Ada.Text_IO.Get_Line (File);
      begin
         if First_Line /= Header then
            return Fail (Line_No, "unsupported LOAM Actual header");
         end if;
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         Line_No := Line_No + 1;
         declare
            Line  : constant String := Ada.Text_IO.Get_Line (File);
            Kind  : constant String := Field (Line, 1);
            Count : constant Natural := Field_Count (Line);
         begin
            if not In_Tx then
               if Kind /= "TX" then
                  return Fail (Line_No, "expected TX row");
               elsif Count < 4 then
                  return Fail (Line_No, "malformed TX row");
               end if;

               declare
                  Event_Text : constant String := Field (Line, 2);
                  Date_Text  : constant String := Field (Line, 3);
                  Mode       : constant String := Field (Line, 4);
                  Parsed_Date : Date_Type;
                  Desc       : constant String :=
                    (if Mode = "DESC" then Remainder_After (Line, 4) else "");
               begin
                  if not Valid_Token (Event_Text) then
                     return Fail (Line_No, "invalid Event identity");
                  elsif Event_Exists
                    (Result.Events, (Token => Make_Token (Event_Text)))
                  then
                     return Fail (Line_No, "duplicate Event identity");
                  elsif not Parse_Iso_Date (Date_Text, Parsed_Date) then
                     return Fail (Line_No, "invalid occurrence date");
                  elsif Mode = "NODESC" and then Count /= 4 then
                     return Fail (Line_No, "malformed NODESC TX row");
                  elsif Mode = "DESC"
                    and then (Count < 5
                              or else Desc'Length = 0
                              or else Desc'Length > Max_Description_Length)
                  then
                     return Fail (Line_No, "invalid Event description");
                  elsif Mode /= "NODESC" and then Mode /= "DESC" then
                     return Fail (Line_No, "unknown TX description mode");
                  elsif Validity_Entries.Count = Validity_Count_Type'Last
                    or else Metadata_Entries.Count = Metadata_Count'Last
                  then
                     return Fail (Line_No, "HRA-N Actual bridge capacity exceeded");
                  end if;

                  Reset_Current;
                  Current_Id := (Token => Make_Token (Event_Text));
                  Current_Date := Parsed_Date;
                  if Mode = "DESC" then
                     for C of Desc loop
                        if C = ASCII.LF or else C = ASCII.CR then
                           return Fail (Line_No, "invalid Event description");
                        end if;
                     end loop;
                     Has_Description := True;
                     Current_Desc := Make_Description (Desc);
                  end if;
                  In_Tx := True;
               end;

            elsif Kind = "EFFECT" then
               if Count /= 4 then
                  return Fail (Line_No, "malformed EFFECT row");
               elsif Current_Effects.Count = Effect_Count_Type'Last then
                  return Fail (Line_No, "too many Effects in one Event");
               end if;
               declare
                  Locus_Text   : constant String := Field (Line, 2);
                  Measure_Text : constant String := Field (Line, 3);
                  Amount_Text  : constant String := Field (Line, 4);
                  Amount       : Quanta_Type;
               begin
                  if not Valid_Token (Locus_Text)
                    or else not Valid_Token (Measure_Text)
                    or else not Parse_Quanta (Amount_Text, Amount)
                  then
                     return Fail (Line_No, "invalid EFFECT row");
                  end if;
                  Current_Effects.Count := Current_Effects.Count + 1;
                  Current_Effects.Values (Current_Effects.Count) :=
                    (Key     => No_Effect_Key,
                     Locus   => (Token => Make_Token (Locus_Text)),
                     Measure => (Token => Make_Token (Measure_Text)),
                     Amount  => (Quanta => Amount));
               end;

            elsif Kind = "KEYED-EFFECT" then
               if Count /= 5 then
                  return Fail (Line_No, "malformed KEYED-EFFECT row");
               elsif Current_Effects.Count = Effect_Count_Type'Last then
                  return Fail (Line_No, "too many Effects in one Event");
               end if;
               declare
                  Key_Text     : constant String := Field (Line, 2);
                  Locus_Text   : constant String := Field (Line, 3);
                  Measure_Text : constant String := Field (Line, 4);
                  Amount_Text  : constant String := Field (Line, 5);
                  Amount       : Quanta_Type;
               begin
                  if not Valid_Token (Key_Text)
                    or else not Valid_Token (Locus_Text)
                    or else not Valid_Token (Measure_Text)
                    or else not Parse_Quanta (Amount_Text, Amount)
                  then
                     return Fail (Line_No, "invalid KEYED-EFFECT row");
                  end if;
                  Current_Effects.Count := Current_Effects.Count + 1;
                  Current_Effects.Values (Current_Effects.Count) :=
                    (Key     => Retained_Effect_Key
                                  ((Token => Make_Token (Key_Text))),
                     Locus   => (Token => Make_Token (Locus_Text)),
                     Measure => (Token => Make_Token (Measure_Text)),
                     Amount  => (Quanta => Amount));
               end;

            elsif Kind = "REPLACES" then
               if Count /= 2 or else Current_Replaces.Present then
                  return Fail (Line_No, "malformed or duplicate REPLACES row");
               end if;
               declare
                  Target : constant String := Field (Line, 2);
               begin
                  if not Valid_Token (Target) then
                     return Fail (Line_No, "invalid REPLACES target");
                  end if;
                  Current_Replaces :=
                    (Present => True,
                     Value   => (Token => Make_Token (Target)));
               end;

            elsif Kind = "REVERSAL-OF" then
               if Count /= 2 or else Current_Reverses.Present then
                  return Fail (Line_No, "malformed or duplicate REVERSAL-OF row");
               end if;
               declare
                  Target : constant String := Field (Line, 2);
               begin
                  if not Valid_Token (Target) then
                     return Fail (Line_No, "invalid REVERSAL-OF target");
                  end if;
                  Current_Reverses :=
                    (Present => True,
                     Value   => (Token => Make_Token (Target)));
               end;

            elsif Kind = "ENDTX" then
               if Count /= 1 then
                  return Fail (Line_No, "malformed ENDTX row");
               elsif not Keys_Are_Unique (Current_Effects) then
                  return Fail (Line_No, "duplicate retained Effect key");
               end if;

               declare
                  Ev : constant Event :=
                    Make_Event (Current_Id, Current_Effects);
               begin
                  if Current_Effects.Count > 0
                    and then not Is_Balanced_Per_Measure (Ev)
                  then
                     return Fail (Line_No, "Event fails per-Measure conservation");
                  end if;

                  Result.Events.Append (Ev);

                  Validity_Entries.Count := Validity_Entries.Count + 1;
                  Validity_Entries.Values (Validity_Entries.Count) :=
                    (Event_Id => Current_Id,
                     Valid_On => Current_Date);

                  if Has_Description then
                     if Description_Entries.Count = Description_Count_Type'Last then
                        return Fail
                          (Line_No, "HRA-N description bridge capacity exceeded");
                     end if;
                     Description_Entries.Count := Description_Entries.Count + 1;
                     Description_Entries.Values (Description_Entries.Count) :=
                       (Event_Id => Current_Id,
                        Text     => Current_Desc);
                  end if;

                  Metadata_Entries.Count := Metadata_Entries.Count + 1;
                  Metadata_Entries.Values (Metadata_Entries.Count) :=
                    (Event       => Current_Id,
                     Purpose     =>
                       (Present => False,
                        Value => (Length => 0, Value => [others => ' '])),
                     Replaces    => Current_Replaces,
                     Reverses    => Current_Reverses,
                     Relation    =>
                       (Present => False,
                        Value => (Length => 0, Value => [others => ' '])),
                     Discharge   =>
                       (Present => False,
                        Value => (Length => 0, Value => [others => ' '])));
               end;

               In_Tx := False;
               Reset_Current;

            elsif Kind = "TX" then
               return Fail (Line_No, "missing ENDTX before next TX");
            else
               return Fail
                 (Line_No,
                  "unsupported LOAM Actual row family: " & Kind);
            end if;
         end;
      end loop;

      if In_Tx then
         return Fail (Line_No, "missing final ENDTX");
      end if;

      if not Event_Ids_Are_Unique (Validity_Entries)
        or else not Event_Ids_Are_Unique (Description_Entries)
        or else not Metadata_Event_Ids_Are_Unique (Metadata_Entries)
      then
         return Fail (Line_No, "duplicate Event identity in decoded evidence");
      elsif not Replacement_References_Are_Closed (Metadata_Entries)
        or else not Replacements_Are_One_To_One (Metadata_Entries)
        or else not Replacements_Are_Acyclic (Metadata_Entries)
      then
         return Fail (Line_No, "invalid Event replacement topology");
      elsif not Reversal_References_Are_Closed (Metadata_Entries)
        or else not Reversals_Are_One_To_One (Metadata_Entries)
        or else not Reversals_Have_No_Chains (Metadata_Entries)
      then
         return Fail (Line_No, "invalid reversal topology");
      end if;

      for I in 1 .. Metadata_Entries.Count loop
         if Metadata_Entries.Values (I).Reverses.Present then
            declare
               Reversal_Event : Event;
               Target_Event   : Event;
               Have_Reversal  : Boolean;
               Have_Target    : Boolean;
            begin
               Find_Event
                 (Result.Events,
                  Metadata_Entries.Values (I).Event,
                  Reversal_Event,
                  Have_Reversal);
               Find_Event
                 (Result.Events,
                  Metadata_Entries.Values (I).Reverses.Value,
                  Target_Event,
                  Have_Target);
               if not Have_Reversal or else not Have_Target then
                  return Fail (Line_No, "reversal endpoint is not readable");
               elsif not Exact_Physical_Inverse
                 (Target_Event, Reversal_Event)
               then
                  return Fail (Line_No, "reversal is not the exact physical inverse");
               end if;
            end;
         end if;
      end loop;

      Result.Validities := Make_Validity_Memory (Validity_Entries);
      Result.Descriptions := Make_Description_Memory (Description_Entries);
      Result.Metadata := Make_Metadata_Memory (Metadata_Entries);
      Result.Success := True;
      Ada.Text_IO.Close (File);
      return Result;

   exception
      when others =>
         return Fail
           (Line_No,
            "unexpected LOAM Actual reader failure");
   end Read_Loam_Actual_File;

end HRA_N.Storage.Loam_Actual_Reader;
