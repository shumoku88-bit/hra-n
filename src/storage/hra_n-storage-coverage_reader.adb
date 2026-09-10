-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Coverage_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Coverage_Reader is

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
     (Result   : in out Read_Coverage_Result;
      Line_Num : Natural;
      Msg      : String) return Read_Coverage_Result
   is
   begin
      Result.Success      := False;
      Result.Error_Line   := Line_Num;
      Result.Error_Len    := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Error;

   function Read_Coverage_File (Path : String) return Read_Coverage_Result is
      File        : File_Type;
      Result      : Read_Coverage_Result;
      Line_Num    : Natural := 0;
      Coords      : Coordinate_List;
      Fields      : Field_Array;
      Field_Count : Natural;
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

            if Line'Length > 0 then
               Split_Tabs (Line, Fields, Field_Count);

               if Line_Num = 1 then
                  if Field_Count /= 2
                    or else Line (Fields (1).First .. Fields (1).Last) /= "LOAM-ZERO-ORIGIN-COVERAGE"
                    or else Line (Fields (2).First .. Fields (2).Last) /= "1"
                  then
                     Close (File);
                     return Set_Error (Result, 1, "Invalid header, expected LOAM-ZERO-ORIGIN-COVERAGE 1");
                  end if;
               else
                  if Field_Count > 0 then
                     declare
                        Tag : constant String := Line (Fields (1).First .. Fields (1).Last);
                     begin
                        if Tag = "COORDINATE" then
                           if Field_Count /= 3 then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Malformed COORDINATE row");
                           end if;

                           if Coords.Count = Max_Coverage_Coordinates then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Too many coverage coordinates");
                           end if;

                           declare
                              Locus_Str   : constant String := Line (Fields (2).First .. Fields (2).Last);
                              Measure_Str : constant String := Line (Fields (3).First .. Fields (3).Last);
                              New_Coord   : Coordinate_Type;
                           begin
                              New_Coord.Locus   := (Token => Make_Token (Locus_Str));
                              New_Coord.Measure := (Token => Make_Token (Measure_Str));

                              Coords.Count := Coords.Count + 1;
                              Coords.Values (Coords.Count) := New_Coord;
                           end;
                        else
                           Close (File);
                           return Set_Error (Result, Line_Num, "Unknown tag in coverage file: " & Tag);
                        end if;
                     end;
                  end if;
               end if;
            end if;
         end;
      end loop;

      Close (File);

      if not Coordinates_Are_Unique (Coords) then
         return Set_Error (Result, Line_Num, "Duplicate coordinates in coverage evidence");
      end if;

      Result.Coverage := Make_Coverage (Coords);
      Result.Success  := True;
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected error reading coverage file");
   end Read_Coverage_File;

end HRA_N.Storage.Coverage_Reader;
