-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Actual_Routing_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Actual_Routing_Reader is

   type Field_Slice is record
      First : Positive;
      Last  : Natural;
   end record;

   type Field_Array is array (1 .. 6) of Field_Slice;

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

   function Read_Actual_Routing_File (Path : String) return Read_Result is
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
            return Set_Error (Result, 0, "Cannot open actual routing file: " & Path);
      end;

      while not End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, F_Count);

               if Line_Num = 1 then
                  if F_Count /= 2
                    or else Line (Fields (1).First .. Fields (1).Last) /= "LOAM-ACTUAL-ROUTING"
                    or else Line (Fields (2).First .. Fields (2).Last) /= "1"
                  then
                     Close (File);
                     return Set_Error (Result, 1, "Invalid LOAM-ACTUAL-ROUTING 1 header");
                  end if;
               else
                  --  Format: ROUTE <locus> INITIAL MANAGED <purpose>
                  if F_Count /= 5
                    or else Line (Fields (1).First .. Fields (1).Last) /= "ROUTE"
                    or else Line (Fields (3).First .. Fields (3).Last) /= "INITIAL"
                    or else Line (Fields (4).First .. Fields (4).Last) /= "MANAGED"
                  then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Malformed ROUTE row");
                  end if;

                  declare
                     Locus_Str   : constant String := Line (Fields (2).First .. Fields (2).Last);
                     Purpose_Str : constant String := Line (Fields (5).First .. Fields (5).Last);
                  begin
                     if Result.Map.Count = Max_Routing_Entries then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Routing map full");
                     end if;

                     Result.Map.Count := Result.Map.Count + 1;
                     Result.Map.Entries (Result.Map.Count) :=
                       (Locus   => (Token => Make_Token (Locus_Str)),
                        Purpose => Make_Token (Purpose_Str));
                  end;
               end if;
            end if;
         end;
      end loop;
      Close (File);

      Result.Success := True;
      return Result;
   end Read_Actual_Routing_File;

end HRA_N.Storage.Actual_Routing_Reader;
