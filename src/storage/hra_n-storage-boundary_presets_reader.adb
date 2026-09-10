-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Boundary_Presets_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Boundary_Presets_Reader is

   function Set_Error
     (Result   : in out Read_Result;
      Line_Num : Natural;
      Msg      : String) return Read_Result
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
     (Text  : String;
      Year  : out Natural;
      Month : out Natural;
      Day   : out Natural) return Boolean
   is
   begin
      Year  := 0;
      Month := 0;
      Day   := 0;

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

         Year  := Y_Val;
         Month := M_Val;
         Day   := D_Val;
         return True;
      exception
         when others =>
            return False;
      end;
   end Parse_Iso_Date;

   function Read_Boundary_Presets_File (Path : String) return Read_Result is
      Result   : Read_Result;
      File     : File_Type;
      Line_Num : Natural := 0;
      Fields   : Field_Array;
      F_Count  : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open boundary presets file: " & Path);
      end;

      while not End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, F_Count);

               if F_Count /= 3 then
                  Close (File);
                  return Set_Error (Result, Line_Num, "Malformed boundary preset row (expected Name, Start, End)");
               end if;

               declare
                  Name_Str  : constant String := Line (Fields (1).First .. Fields (1).Last);
                  Start_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                  End_Str   : constant String := Line (Fields (3).First .. Fields (3).Last);
                  SY, SM, SD : Natural;
                  EY, EM, ED : Natural;
               begin
                  if not Parse_Iso_Date (Start_Str, SY, SM, SD) then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Invalid start date: " & Start_Str);
                  end if;

                  if not Parse_Iso_Date (End_Str, EY, EM, ED) then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Invalid end date: " & End_Str);
                  end if;

                  if Result.Memory.Count = Max_Presets then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Presets memory full");
                  end if;

                  Result.Memory.Count := Result.Memory.Count + 1;
                  Result.Memory.Presets (Result.Memory.Count) :=
                    (Name        => Make_Token (Name_Str),
                     Start_Year  => SY,
                     Start_Month => SM,
                     Start_Day   => SD,
                     End_Year    => EY,
                     End_Month   => EM,
                     End_Day     => ED);
               end;
            end if;
         end;
      end loop;
      Close (File);

      Result.Success := True;
      return Result;
   end Read_Boundary_Presets_File;

   function Find_Preset
     (Mem    : Presets_Memory;
      Name   : String;
      Preset : out Boundary_Preset) return Boolean
   is
   begin
      Preset := Empty_Preset;
      for I in 1 .. Mem.Count loop
         if Mem.Presets (I).Name.Length = Name'Length
           and then Mem.Presets (I).Name.Value (1 .. Name'Length) = Name
         then
            Preset := Mem.Presets (I);
            return True;
         end if;
      end loop;
      return False;
   end Find_Preset;

end HRA_N.Storage.Boundary_Presets_Reader;
