-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Description_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Description_Reader is

   procedure Split_Tabs
     (Line   : String;
      Fields : out Field_Array;
      Count  : out Natural)
   is
      Pos   : Positive := Line'First;
      Idx   : Natural  := 0;
      Start : Positive;
   begin
      Count := 0;
      if Line'Length = 0 then
         return;
      end if;

      while Pos <= Line'Last and then Idx < Fields'Last loop
         Start := Pos;
         while Pos <= Line'Last and then Line (Pos) /= ASCII.HT loop
            Pos := Pos + 1;
         end loop;

         Idx := Idx + 1;
         Fields (Idx) := (First => Start, Last => Pos - 1);

         if Pos <= Line'Last and then Line (Pos) = ASCII.HT then
            Pos := Pos + 1;
            --  Handle trailing tab creating an empty final field.
            if Pos > Line'Last and then Idx < Fields'Last then
               Idx := Idx + 1;
               Fields (Idx) := (First => Pos, Last => Pos - 1);
            end if;
         end if;
      end loop;

      Count := Idx;
   end Split_Tabs;

   function Set_Error
     (Result   : in out Read_Description_Result;
      Line_Num : Natural;
      Msg      : String) return Read_Description_Result
   is
   begin
      Result.Success      := False;
      Result.Error_Line   := Line_Num;
      Result.Error_Len    := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Error;

   function Unescape_Text
     (Raw     : String;
      Decoded : out Description_Text) return Boolean
   is
      Buf : String (1 .. Max_Description_Length) := [others => ' '];
      Len : Natural := 0;
      Pos : Positive := Raw'First;
   begin
      while Pos <= Raw'Last loop
         if Raw (Pos) = '\' then
            Pos := Pos + 1;
            if Pos > Raw'Last then
               --  Dangling backslash fails closed.
               return False;
            end if;

            if Len >= Max_Description_Length then
               return False;
            end if;

            case Raw (Pos) is
               when '\' =>
                  Len := Len + 1;
                  Buf (Len) := '\';
               when 'n' =>
                  Len := Len + 1;
                  Buf (Len) := ASCII.LF;
               when 'r' =>
                  Len := Len + 1;
                  Buf (Len) := ASCII.CR;
               when 't' =>
                  Len := Len + 1;
                  Buf (Len) := ASCII.HT;
               when others =>
                  --  Unknown escape sequence fails closed.
                  return False;
            end case;
         else
            if Len >= Max_Description_Length then
               return False;
            end if;
            Len := Len + 1;
            Buf (Len) := Raw (Pos);
         end if;
         Pos := Pos + 1;
      end loop;

      Decoded.Length := Len;
      Decoded.Value (1 .. Len) := Buf (1 .. Len);
      return True;
   end Unescape_Text;

   function Read_Description_File (Path : String) return Read_Description_Result is
      Result   : Read_Description_Result;
      File     : File_Type;
      Line_Num : Natural := 0;
      Entries  : Description_Entry_List;

      Header_Expected : constant String :=
        "LOAM-EVENT-DESCRIPTION-MEMORY" & ASCII.HT & "1";
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open file: " & Path);
      end;

      while not End_Of_File (File) loop
         declare
            Line : constant String := Get_Line (File);
         begin
            Line_Num := Line_Num + 1;

            if Line_Num = 1 then
               if Line /= Header_Expected then
                  Close (File);
                  return Set_Error (Result, 1, "Invalid header: expected " & Header_Expected);
               end if;
            elsif Line'Length > 0 then
               declare
                  Fields : Field_Array;
                  Count  : Natural;
               begin
                  Split_Tabs (Line, Fields, Count);

                  --  Rows must have at least 2 fields: DESC, event_id, [text].
                  if Count < 2 or else Count > 3 then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Malformed row: expected 2 or 3 fields");
                  end if;

                  declare
                     Kind_Slice  : constant String :=
                       Line (Fields (1).First .. Fields (1).Last);
                     Id_Slice    : constant String :=
                       Line (Fields (2).First .. Fields (2).Last);
                     Desc_Slice  : constant String :=
                       (if Count >= 3 and then Fields (3).First <= Fields (3).Last
                        then Line (Fields (3).First .. Fields (3).Last)
                        else "");
                  begin
                     if Kind_Slice /= "DESC" then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Unknown record kind: " & Kind_Slice);
                     end if;

                     if Id_Slice'Length > Max_Token_Length then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Token too long: " & Id_Slice);
                     end if;

                     declare
                        Ev_Id   : constant Event_Id :=
                          (Token => Make_Token (Id_Slice));
                        Desc_Tx : Description_Text;
                     begin
                        if not Unescape_Text (Desc_Slice, Desc_Tx) then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Malformed escape sequence in text");
                        end if;

                        --  Fail closed on duplicate EventId.
                        for I in 1 .. Entries.Count loop
                           if Equal_Token (Entries.Values (I).Event_Id.Token, Ev_Id.Token) then
                              Close (File);
                              return Set_Error
                                (Result, Line_Num, "Duplicate EventId: " & Id_Slice);
                           end if;
                        end loop;

                        if Entries.Count = Max_Description_Entries then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Memory capacity exceeded");
                        end if;

                        Entries.Count := Entries.Count + 1;
                        Entries.Values (Entries.Count) :=
                          (Event_Id => Ev_Id,
                           Text     => Desc_Tx);
                     end;
                  end;
               end;
            end if;
         end;
      end loop;

      Close (File);

      if Line_Num = 0 then
         return Set_Error (Result, 0, "Empty file");
      end if;

      Result.Success := True;
      Result.Memory  := Make_Description_Memory (Entries);
      return Result;

   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected exception during read");
   end Read_Description_File;

end HRA_N.Storage.Description_Reader;
