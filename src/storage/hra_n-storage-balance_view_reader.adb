-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Balance_View_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Directories;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;
with HRA_N.Core.Types;   use HRA_N.Core.Types;

package body HRA_N.Storage.Balance_View_Reader is

   function Set_Error
     (Result : in out Read_Balance_View_Result;
      Line   : Natural;
      Msg    : String) return Read_Balance_View_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Line   := Line;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Is_Valid_Token_Char (C : Character) return Boolean is
   begin
      return C in 'a' .. 'z'
        or else C in 'A' .. 'Z'
        or else C in '0' .. '9'
        or else C = '-'
        or else C = '_'
        or else C = ':'
        or else C = '.';
   end Is_Valid_Token_Char;

   function Is_Valid_Token (S : String) return Boolean is
   begin
      if S'Length = 0 or else S'Length > Max_Token_Length then
         return False;
      end if;
      for I in S'Range loop
         if not Is_Valid_Token_Char (S (I)) then
            return False;
         end if;
      end loop;
      return True;
   end Is_Valid_Token;

   function Read_Balance_View_File (Path : String) return Read_Balance_View_Result is
      Result  : Read_Balance_View_Result;
      File    : Ada.Text_IO.File_Type;
      Line_No : Natural := 0;
   begin
      if not Ada.Directories.Exists (Path) then
         Result.Success := True;
         Result.Coordinates.Count := 0;
         return Result;
      end if;

      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Could not open balance view file: " & Path);
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Raw_Line : constant String := Ada.Text_IO.Get_Line (File);
            Line     : constant String := Trim (Raw_Line, Ada.Strings.Both);
         begin
            Line_No := Line_No + 1;
            if Line'Length > 0 and then Line (Line'First) /= '#' then
               declare
                  Tab_Pos : constant Natural := Index (Line, "" & ASCII.HT);
               begin
                  if Tab_Pos = 0 then
                     Ada.Text_IO.Close (File);
                     return Set_Error (Result, Line_No, "Malformed balance-view row (missing TAB)");
                  end if;

                  declare
                     Locus_Str : constant String := Line (Line'First .. Tab_Pos - 1);
                     Rest      : constant String := Line (Tab_Pos + 1 .. Line'Last);
                     Tab_2     : constant Natural := Index (Rest, "" & ASCII.HT);
                  begin
                     if Tab_2 /= 0 then
                        Ada.Text_IO.Close (File);
                        return Set_Error (Result, Line_No, "Malformed balance-view row (too many columns)");
                     end if;

                     if not Is_Valid_Token (Locus_Str) then
                        Ada.Text_IO.Close (File);
                        return Set_Error (Result, Line_No, "Invalid locus token: " & Locus_Str);
                     end if;

                     if not Is_Valid_Token (Rest) then
                        Ada.Text_IO.Close (File);
                        return Set_Error (Result, Line_No, "Invalid measure token: " & Rest);
                     end if;

                     declare
                        Coord : constant Coordinate_Type :=
                          (Locus   => (Token => Make_Token (Locus_Str)),
                           Measure => (Token => Make_Token (Rest)));
                        Already_Present : Boolean := False;
                     begin
                        for I in 1 .. Result.Coordinates.Count loop
                           if Equal_Coordinate (Result.Coordinates.Values (I), Coord) then
                              Already_Present := True;
                              exit;
                           end if;
                        end loop;

                        if not Already_Present then
                           if Result.Coordinates.Count = Max_Balance_Coordinates then
                              Ada.Text_IO.Close (File);
                              return Set_Error (Result, Line_No, "Too many balance coordinates");
                           end if;

                           Result.Coordinates.Count := Result.Coordinates.Count + 1;
                           Result.Coordinates.Values (Result.Coordinates.Count) := Coord;
                        end if;
                     end;
                  end;
               end;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);
      Result.Success := True;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Set_Error (Result, Line_No, "Error reading balance view file");
   end Read_Balance_View_File;

end HRA_N.Storage.Balance_View_Reader;
