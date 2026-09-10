-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Validity_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Validity_Reader is

   type Field_Slice is record
      First : Positive;
      Last  : Natural;
   end record;

   type Field_Array is array (1 .. 8) of Field_Slice;

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
         end if;
      end loop;

      Count := Idx;
   end Split_Tabs;

   function Set_Error
     (Result   : in out Read_Validity_Result;
      Line_Num : Natural;
      Msg      : String) return Read_Validity_Result
   is
   begin
      Result.Success      := False;
      Result.Error_Line   := Line_Num;
      Result.Error_Len    := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Error;

   function Parse_Iso_Date
     (Text : String;
      Date : out Date_Type) return Boolean
   is
   begin
      Date := (Year => 2026, Month => 1, Day => 1);
      if Text'Length /= 10 then
         return False;
      end if;

      if Text (Text'First + 4) /= '-' or else Text (Text'First + 7) /= '-' then
         return False;
      end if;

      for I in Text'Range loop
         if I /= Text'First + 4 and then I /= Text'First + 7 then
            if Text (I) not in '0' .. '9' then
               return False;
            end if;
         end if;
      end loop;

      declare
         Y_Val : constant Integer :=
           Integer'Value (Text (Text'First .. Text'First + 3));
         M_Val : constant Integer :=
           Integer'Value (Text (Text'First + 5 .. Text'First + 6));
         D_Val : constant Integer :=
           Integer'Value (Text (Text'First + 8 .. Text'First + 9));
      begin
         if Y_Val not in Year_Type or else M_Val not in Month_Type or else D_Val not in Day_Type then
            return False;
         end if;

         if not Is_Valid_Date (Y_Val, M_Val, D_Val) then
            return False;
         end if;

         Date := Make_Date (Y_Val, M_Val, D_Val);
         return True;
      exception
         when others =>
            return False;
      end;
   end Parse_Iso_Date;

   function Read_Validity_File (Path : String) return Read_Validity_Result is
      File        : File_Type;
      Result      : Read_Validity_Result;
      Line_Num    : Natural := 0;
      Entries     : Validity_Entry_List;
      Fields      : Field_Array;
      Field_Count : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open validity file: " & Path);
      end;

      while not End_Of_File (File) loop
         declare
            Line : constant String := Get_Line (File);
         begin
            Line_Num := Line_Num + 1;

            if Line'Length > 0 then
               Split_Tabs (Line, Fields, Field_Count);

               if Line_Num = 1 then
                  if Field_Count /= 2
                    or else Line (Fields (1).First .. Fields (1).Last) /= "LOAM-ACTUAL-VALIDITY-HISTORY"
                    or else Line (Fields (2).First .. Fields (2).Last) /= "2"
                  then
                     Close (File);
                     return Set_Error (Result, 1, "Invalid header, expected LOAM-ACTUAL-VALIDITY-HISTORY 2");
                  end if;
               else
                  if Field_Count > 0 then
                     declare
                        Tag : constant String := Line (Fields (1).First .. Fields (1).Last);
                     begin
                        if Tag = "BASE" then
                           if Field_Count /= 3 then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Malformed BASE row (expected 3 fields)");
                           end if;

                           if Entries.Count = Max_Validity_Entries then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Too many validity entries");
                           end if;

                           declare
                              Ev_Str   : constant String := Line (Fields (2).First .. Fields (2).Last);
                              Date_Str : constant String := Line (Fields (3).First .. Fields (3).Last);
                              Parsed_D : Date_Type;
                           begin
                              if not Parse_Iso_Date (Date_Str, Parsed_D) then
                                 Close (File);
                                 return Set_Error (Result, Line_Num, "Invalid calendar date: " & Date_Str);
                              end if;

                              Entries.Count := Entries.Count + 1;
                              Entries.Values (Entries.Count) :=
                                (Event_Id => (Token => Make_Token (Ev_Str)),
                                 Valid_On => Parsed_D);
                           end;
                        else
                           Close (File);
                           return Set_Error (Result, Line_Num, "Unknown tag in validity file: " & Tag);
                        end if;
                     end;
                  end if;
               end if;
            end if;
         end;
      end loop;

      Close (File);

      if not Event_Ids_Are_Unique (Entries) then
         return Set_Error (Result, Line_Num, "Duplicate EventIds in validity evidence");
      end if;

      Result.Memory  := Make_Validity_Memory (Entries);
      Result.Success := True;
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected error reading validity file");
   end Read_Validity_File;

end HRA_N.Storage.Validity_Reader;
