-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Journal_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with HRA_N.Core.Types;              use HRA_N.Core.Types;
with HRA_N.Storage.HRA_Tokenizer;   use HRA_N.Storage.HRA_Tokenizer;

package body HRA_N.Storage.Journal_Reader is

   function Parse_Integer (S : String; Val : out Long_Long_Integer) return Boolean is
      Sign  : Long_Long_Integer := 1;
      First : Positive := S'First;
      Res   : Long_Long_Integer := 0;
   begin
      if S'Length = 0 then
         return False;
      end if;

      if S (First) = '-' then
         Sign := -1;
         First := First + 1;
      elsif S (First) = '+' then
         First := First + 1;
      end if;

      if First > S'Last then
         return False;
      end if;

      for I in First .. S'Last loop
         if S (I) not in '0' .. '9' then
            return False;
         end if;
         Res := Res * 10 + Long_Long_Integer (Character'Pos (S (I)) - Character'Pos ('0'));
      end loop;

      Val := Res * Sign;
      return True;
   end Parse_Integer;

   procedure Parse_Flow
     (Tok     : String;
      Locus   : out Token_Text;
      Measure : out Token_Text;
      Amount  : out Quanta_Type;
      Success : out Boolean)
   is
      Last_Colon : Natural := 0;
      Prev_Colon : Natural := 0;
      Amt_Val    : Long_Long_Integer;
   begin
      Success := False;
      Locus   := Make_Token ("");
      Measure := Make_Token ("jpy");
      Amount  := Zero_Quanta;

      for I in Tok'Range loop
         if Tok (I) = ':' then
            Prev_Colon := Last_Colon;
            Last_Colon := I;
         end if;
      end loop;

      if Last_Colon = 0 then
         return;
      end if;

      --  Check if part after last colon is integer (e.g. locus:100 or locus:sub:-192)
      if Parse_Integer (Tok (Last_Colon + 1 .. Tok'Last), Amt_Val) then
         Amount  := Quanta_Type (Amt_Val);
         Measure := Make_Token ("jpy");
         Locus   := Make_Token (Tok (Tok'First .. Last_Colon - 1));
         Success := True;
      elsif Prev_Colon > 0
        and then Parse_Integer (Tok (Prev_Colon + 1 .. Last_Colon - 1), Amt_Val)
      then
         --  locus:100:usd or locus:sub:100:jpy
         Amount  := Quanta_Type (Amt_Val);
         Measure := Make_Token (Tok (Last_Colon + 1 .. Tok'Last));
         Locus   := Make_Token (Tok (Tok'First .. Prev_Colon - 1));
         Success := True;
      end if;
   end Parse_Flow;

   function Read_Journal_File (Path : String) return Journal_Result is
      File      : Ada.Text_IO.File_Type;
      Result    : Journal_Result;
      Line_Num  : Natural := 0;

      Val_List  : Validity_Entry_List;
      Desc_List : Description_Entry_List;

      procedure Set_Error (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Line := Line_Num;
         Result.Error_Len := L;
         Result.Error_Reason (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Set_Error;

   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      exception
         when others =>
            Set_Error ("Cannot open journal file: " & Path);
            return Result;
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line     : constant String := Ada.Text_IO.Get_Line (File);
            Tokens   : Token_Array;
            Count    : Natural;
         begin
            Tokenize_Line (Line, Tokens, Count);

            if Count > 0 then
               declare
                  Tag : constant String := Slice (Line, Tokens (1));
               begin
                  if Tag /= "TX" then
                     Set_Error ("Expected 'TX' record header, found: " & Tag);
                     Ada.Text_IO.Close (File);
                     return Result;
                  end if;

                  if Count < 4 then
                     Set_Error ("Malformed TX record: insufficient tokens");
                     Ada.Text_IO.Close (File);
                     return Result;
                  end if;

                  declare
                     Ev_Id_Str   : constant String := Slice (Line, Tokens (2));
                     Date_Str    : constant String := Slice (Line, Tokens (3));
                     Parsed_Date : Date_Type;
                     Effects     : Effect_List;
                     Note_Text   : Description_Text := (Length => 0, Value => [others => ' ']);
                     Has_Note    : Boolean := False;
                  begin
                     if not Parse_Iso_Date (Date_Str, Parsed_Date) then
                        Set_Error ("Invalid ISO date in TX record: " & Date_Str);
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     --  Parse flows and optional metadata
                     for T in 4 .. Count loop
                        declare
                           Tok_Str : constant String := Slice (Line, Tokens (T));
                        begin
                           if Tokens (T).Kind = Tok_Quoted then
                              Note_Text := Make_Description (Tok_Str);
                              Has_Note := True;
                           elsif Tok_Str'Length > 0 and then Tok_Str (Tok_Str'First) = '@' then
                              null; -- Purpose tag
                           elsif Tok_Str'Length >= 9 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 8) = "replaces:" then
                              null; -- Replaces metadata
                           elsif Tok_Str'Length >= 9 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 8) = "relation:" then
                              null; -- Relation metadata
                           elsif Tok_Str'Length >= 11 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 10) = "discharges:" then
                              null; -- Discharge metadata
                           else
                              --  Must be a flow
                              declare
                                 Locus   : Token_Text;
                                 Measure : Token_Text;
                                 Amt     : Quanta_Type;
                                 Flow_Ok : Boolean;
                                 Key_Str : constant String := "f" & Natural'Image (Effects.Count + 1);
                              begin
                                 Parse_Flow (Tok_Str, Locus, Measure, Amt, Flow_Ok);
                                 if not Flow_Ok then
                                    Set_Error ("Malformed flow token: " & Tok_Str);
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;

                                 Effects.Count := Effects.Count + 1;
                                 Effects.Values (Effects.Count) :=
                                   (Key     => (Token => Make_Token (Key_Str)),
                                    Locus   => (Token => Locus),
                                    Measure => (Token => Measure),
                                    Amount  => (Quanta => Amt));
                              end;
                           end if;
                        end;
                     end loop;

                     if Effects.Count = 0 then
                        Set_Error ("TX record has no flows");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     --  Construct and append Event
                     declare
                        Ev : constant Event := Make_Event
                          (Id      => (Token => Make_Token (Ev_Id_Str)),
                           Effects => Effects);
                     begin
                        Result.Events.Append (Ev);
                     end;

                     --  Record Validity fact
                     if Val_List.Count < Max_Validity_Entries then
                        Val_List.Count := Val_List.Count + 1;
                        Val_List.Values (Val_List.Count) :=
                          (Event_Id => (Token => Make_Token (Ev_Id_Str)),
                           Valid_On => Parsed_Date);
                     end if;

                     --  Record Description fact
                     if Has_Note and then Desc_List.Count < Max_Description_Entries then
                        Desc_List.Count := Desc_List.Count + 1;
                        Desc_List.Values (Desc_List.Count) :=
                          (Event_Id => (Token => Make_Token (Ev_Id_Str)),
                           Text     => Note_Text);
                     end if;
                  end;
               end;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);

      --  Assemble encapsulated memory structures
      if Event_Ids_Are_Unique (Val_List) then
         Result.Validities := Make_Validity_Memory (Val_List);
      else
         Set_Error ("Duplicate Event_Id in journal validity facts");
         return Result;
      end if;

      if Event_Ids_Are_Unique (Desc_List) then
         Result.Descriptions := Make_Description_Memory (Desc_List);
      else
         Set_Error ("Duplicate Event_Id in journal description facts");
         return Result;
      end if;

      Result.Success := True;
      return Result;

   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Set_Error ("Unexpected I/O exception reading journal");
         return Result;
   end Read_Journal_File;

end HRA_N.Storage.Journal_Reader;
