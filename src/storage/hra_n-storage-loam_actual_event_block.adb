-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Event_Block
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Loam_Actual_Event_Block is

   Empty_Effects : constant Effect_List :=
     (Count => 0, Values => [others => Empty_Effect]);

   Empty_Id : constant Event_Id :=
     (Token => (Length => 0, Value => [others => ' ']));

   Empty_Event : constant Event :=
     Make_Event (Empty_Id, Empty_Effects);

   Empty_Validity : constant Validity_Entry :=
     (Event_Id => Empty_Id,
      Valid_On => (Year => 2026, Month => 1, Day => 1));

   Empty_Description : constant Description_Entry :=
     (Event_Id => Empty_Id,
      Text     => (Length => 0, Value => [others => ' ']));

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

   function Decode_Event_Block (Block : String) return Event_Block_Result is
      Result : Event_Block_Result :=
        (Success         => False,
         Value           => Empty_Event,
         Validity        => Empty_Validity,
         Has_Description => False,
         Description     => Empty_Description,
         Metadata        => Empty_Entry,
         Error_Line      => 0,
         Error_Reason    => [others => ' '],
         Error_Len       => 0);

      Current_Id       : Event_Id := Empty_Id;
      Current_Date     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Current_Effects  : Effect_List := Empty_Effects;
      Current_Replaces : Optional_Event_Id :=
        (Present => False, Value => Empty_Id);
      Current_Reverses : Optional_Event_Id :=
        (Present => False, Value => Empty_Id);
      Has_Description  : Boolean := False;
      Current_Desc     : Description_Text :=
        (Length => 0, Value => [others => ' ']);

      Position : Natural := Block'First;
      Line_No  : Natural := 0;

      procedure Set_Error (At_Line : Natural; Message : String) is
         N : constant Natural :=
           Natural'Min (Message'Length, Result.Error_Reason'Length);
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
         Message : String) return Event_Block_Result
      is
      begin
         Set_Error (At_Line, Message);
         return Result;
      end Fail;

   begin
      if Block'Length = 0 then
         return Fail (0, "Event block is empty");
      elsif Block (Block'Last) /= ASCII.LF then
         return Fail (0, "Event block must end with newline");
      end if;

      while Position <= Block'Last loop
         declare
            Line_LF : Natural := 0;
         begin
            for I in Position .. Block'Last loop
               if Block (I) = ASCII.LF then
                  Line_LF := I;
                  exit;
               end if;
            end loop;

            if Line_LF = 0 then
               return Fail (Line_No, "missing Event block newline");
            end if;

            Line_No := Line_No + 1;

            declare
               Line : constant String := Block (Position .. Line_LF - 1);
               Kind : constant String := Field (Line, 1);
               Count : constant Natural := Field_Count (Line);
            begin
               if Line_No = 1 then
                  if Kind /= "TX" then
                     return Fail (Line_No, "expected TX row");
                  elsif Count < 4 then
                     return Fail (Line_No, "malformed TX row");
                  end if;

                  declare
                     Event_Text  : constant String := Field (Line, 2);
                     Date_Text   : constant String := Field (Line, 3);
                     Mode        : constant String := Field (Line, 4);
                     Parsed_Date : Date_Type;
                     Desc        : constant String :=
                       (if Mode = "DESC" then Remainder_After (Line, 4) else "");
                  begin
                     if not Valid_Token (Event_Text) then
                        return Fail (Line_No, "invalid Event identity");
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
                     end if;

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
                       (Key     =>
                          Retained_Effect_Key
                            ((Token => Make_Token (Key_Text))),
                        Locus   => (Token => Make_Token (Locus_Text)),
                        Measure => (Token => Make_Token (Measure_Text)),
                        Amount  => (Quanta => Amount));
                  end;

               elsif Kind = "REPLACES" then
                  if Count /= 2 or else Current_Replaces.Present then
                     return Fail
                       (Line_No, "malformed or duplicate REPLACES row");
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
                     return Fail
                       (Line_No, "malformed or duplicate REVERSAL-OF row");
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
                  elsif Line_LF /= Block'Last then
                     return Fail (Line_No, "trailing row after ENDTX");
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
                        return Fail
                          (Line_No, "Event fails per-Measure conservation");
                     end if;

                     Result.Success := True;
                     Result.Value := Ev;
                     Result.Validity :=
                       (Event_Id => Current_Id,
                        Valid_On => Current_Date);
                     Result.Has_Description := Has_Description;
                     Result.Description :=
                       (Event_Id => Current_Id,
                        Text     => Current_Desc);
                     Result.Metadata :=
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
                     return Result;
                  end;

               elsif Kind = "TX" then
                  return Fail
                    (Line_No, "missing ENDTX before next TX");
               else
                  return Fail
                    (Line_No,
                     "unsupported LOAM Actual row family: " & Kind);
               end if;
            end;

            Position := Line_LF + 1;
         end;
      end loop;

      return Fail (Line_No, "missing final ENDTX");

   exception
      when others =>
         return Fail
           (Line_No, "unexpected LOAM Actual Event block failure");
   end Decode_Event_Block;

end HRA_N.Storage.Loam_Actual_Event_Block;
