-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Capacity_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Capacity_Reader is

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

   function Read_Capacity_Files
     (Memory_Path    : String;
      Effective_Path : String) return Read_Result
   is
      Result    : Read_Result;
      File      : File_Type;
      Line_Num  : Natural := 0;
      Fields    : Field_Array;
      F_Count   : Natural;

      Have_Mov  : Boolean := False;
      Curr_Mov  : Capacity_Movement := Empty_Capacity_Movement;
   begin
      --  1. Read capacity.loam
      begin
         Open (File, In_File, Memory_Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open capacity memory file: " & Memory_Path);
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
                    or else Line (Fields (1).First .. Fields (1).Last) /= "LOAM-CAPACITY-MEMORY"
                    or else Line (Fields (2).First .. Fields (2).Last) /= "1"
                  then
                     Close (File);
                     return Set_Error (Result, 1, "Invalid LOAM-CAPACITY-MEMORY 1 header");
                  end if;
               else
                  declare
                     Tag : constant String := Line (Fields (1).First .. Fields (1).Last);
                  begin
                     if Tag = "MOVEMENT" then
                        if F_Count /= 3 then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Malformed MOVEMENT row");
                        end if;

                        --  Flush previous movement if any
                        if Have_Mov then
                           if Curr_Mov.Change_Count < 2 then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Movement has fewer than 2 changes");
                           end if;
                           if not Is_Conserved (Curr_Mov) then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Movement violates conservation law (Sum /= 0)");
                           end if;

                           if Result.Memory.Movement_Count = Max_Capacity_Movements then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Capacity movement memory full");
                           end if;

                           Result.Memory.Movement_Count := Result.Memory.Movement_Count + 1;
                           Result.Memory.Movements (Result.Memory.Movement_Count) := Curr_Mov;
                        end if;

                        Curr_Mov := Empty_Capacity_Movement;
                        Curr_Mov.Id := Make_Token (Line (Fields (2).First .. Fields (2).Last));
                        Curr_Mov.Currency := Make_Token (Line (Fields (3).First .. Fields (3).Last));
                        Have_Mov := True;

                     elsif Tag = "CHANGE" then
                        if not Have_Mov then
                           Close (File);
                           return Set_Error (Result, Line_Num, "CHANGE row without MOVEMENT");
                        end if;

                        if Curr_Mov.Change_Count = Max_Changes_Per_Movement then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Too many changes in movement");
                        end if;

                        declare
                           Target_Kind : constant String := Line (Fields (2).First .. Fields (2).Last);
                           Amt_Str     : String (1 .. 32);
                           Amt_Len     : Natural := 0;
                           Amt_Val     : Quanta_Type;
                           Change_Item : Capacity_Change := Empty_Change;
                        begin
                           if Target_Kind = "UNALLOCATED" then
                              if F_Count /= 3 then
                                 Close (File);
                                 return Set_Error (Result, Line_Num, "Malformed CHANGE UNALLOCATED row");
                              end if;
                              Amt_Len := Fields (3).Last - Fields (3).First + 1;
                              Amt_Str (1 .. Amt_Len) := Line (Fields (3).First .. Fields (3).Last);
                              Change_Item.Coord := Make_Unallocated_Coordinate;

                           elsif Target_Kind = "PURPOSE" then
                              if F_Count /= 4 then
                                 Close (File);
                                 return Set_Error (Result, Line_Num, "Malformed CHANGE PURPOSE row");
                              end if;
                              Amt_Len := Fields (4).Last - Fields (4).First + 1;
                              Amt_Str (1 .. Amt_Len) := Line (Fields (4).First .. Fields (4).Last);
                              Change_Item.Coord :=
                                Make_Purpose_Coordinate
                                  (Make_Token (Line (Fields (3).First .. Fields (3).Last)));
                           else
                              Close (File);
                              return Set_Error (Result, Line_Num, "Unknown CHANGE coordinate kind: " & Target_Kind);
                           end if;

                           begin
                              Amt_Val := Quanta_Type'Value (Amt_Str (1 .. Amt_Len));
                           exception
                              when others =>
                                 Close (File);
                                 return Set_Error (Result, Line_Num, "Invalid Quanta integer value");
                           end;

                           Change_Item.Amount := Amt_Val;
                           Curr_Mov.Change_Count := Curr_Mov.Change_Count + 1;
                           Curr_Mov.Changes (Curr_Mov.Change_Count) := Change_Item;
                        end;

                     else
                        Close (File);
                        return Set_Error (Result, Line_Num, "Unknown capacity tag: " & Tag);
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;
      Close (File);

      --  Flush final movement
      if Have_Mov then
         if Curr_Mov.Change_Count < 2 then
            return Set_Error (Result, Line_Num, "Final movement has fewer than 2 changes");
         end if;
         if not Is_Conserved (Curr_Mov) then
            return Set_Error (Result, Line_Num, "Final movement violates conservation law (Sum /= 0)");
         end if;
         if Result.Memory.Movement_Count = Max_Capacity_Movements then
            return Set_Error (Result, Line_Num, "Capacity movement memory full");
         end if;
         Result.Memory.Movement_Count := Result.Memory.Movement_Count + 1;
         Result.Memory.Movements (Result.Memory.Movement_Count) := Curr_Mov;
      end if;

      --  2. Read capacity.loam.effective
      begin
         Open (File, In_File, Effective_Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open capacity effective file: " & Effective_Path);
      end;

      Line_Num := 0;
      while not End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, F_Count);

               if Line_Num = 1 then
                  if F_Count /= 2
                    or else Line (Fields (1).First .. Fields (1).Last) /= "LOAM-CAPACITY-EFFECTIVE"
                    or else Line (Fields (2).First .. Fields (2).Last) /= "1"
                  then
                     Close (File);
                     return Set_Error (Result, 1, "Invalid LOAM-CAPACITY-EFFECTIVE 1 header");
                  end if;
               else
                  if F_Count /= 3 or else Line (Fields (1).First .. Fields (1).Last) /= "EFFECTIVE" then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Malformed EFFECTIVE row");
                  end if;

                  declare
                     Mov_Id_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                     Date_Str   : constant String := Line (Fields (3).First .. Fields (3).Last);
                     Y, M, D    : Natural;
                  begin
                     if not Parse_Iso_Date (Date_Str, Y, M, D) then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Invalid ISO date in EFFECTIVE row: " & Date_Str);
                     end if;

                     if Result.Memory.Effective_Count = Max_Capacity_Movements then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Capacity effective memory full");
                     end if;

                     Result.Memory.Effective_Count := Result.Memory.Effective_Count + 1;
                     Result.Memory.Effective (Result.Memory.Effective_Count) :=
                       (Movement_Id => Make_Token (Mov_Id_Str),
                        Year        => Y,
                        Month       => M,
                        Day         => D);
                  end;
               end if;
            end if;
         end;
      end loop;
      Close (File);

      --  3. Verify evidence completeness
      if not Effective_Evidence_Complete (Result.Memory) then
         return Set_Error (Result, 0, "Capacity movement and effective evidence do not match 1-to-1");
      end if;

      Result.Success := True;
      return Result;
   end Read_Capacity_Files;

end HRA_N.Storage.Capacity_Reader;
