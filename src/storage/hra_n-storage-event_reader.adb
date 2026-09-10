-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Event_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;

package body HRA_N.Storage.Event_Reader is

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

   function Read_Event_Memory_File (Path : String) return Read_Result is
      File         : File_Type;
      Result       : Read_Result;
      Line_Num     : Natural := 0;
      Have_Event   : Boolean := False;
      Curr_Id      : Event_Id;
      Curr_Effects : Effect_List;
      Fields       : Field_Array;
      Field_Count  : Natural;

      procedure Flush_Current_Event is
      begin
         if Have_Event then
            if not Keys_Are_Unique (Curr_Effects) then
               raise Constraint_Error with "Duplicate effect keys in event";
            end if;
            Result.Events.Append (Make_Event (Curr_Id, Curr_Effects));
            Have_Event         := False;
            Curr_Effects.Count := 0;
         end if;
      end Flush_Current_Event;

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
                    or else Line (Fields (1).First .. Fields (1).Last) /= "LOAM-EVENT-MEMORY"
                    or else Line (Fields (2).First .. Fields (2).Last) /= "1"
                  then
                     Close (File);
                     return Set_Error (Result, 1, "Invalid header, expected LOAM-EVENT-MEMORY 1");
                  end if;
               else
                  if Field_Count > 0 then
                     declare
                        Tag : constant String := Line (Fields (1).First .. Fields (1).Last);
                     begin
                        if Tag = "EVENT" then
                           if Field_Count /= 2 then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Malformed EVENT row");
                           end if;

                           Flush_Current_Event;

                           Curr_Id            := (Token => Make_Token (Line (Fields (2).First .. Fields (2).Last)));
                           Curr_Effects.Count := 0;
                           Have_Event         := True;

                        elsif Tag = "EFFECT" then
                           if not Have_Event then
                              Close (File);
                              return Set_Error (Result, Line_Num, "EFFECT row without preceding EVENT");
                           end if;

                           if Field_Count /= 5 then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Malformed EFFECT row");
                           end if;

                           if Curr_Effects.Count = Max_Effects_Per_Event then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Too many effects in event");
                           end if;

                           declare
                              Key_Str     : constant String := Line (Fields (2).First .. Fields (2).Last);
                              Locus_Str   : constant String := Line (Fields (3).First .. Fields (3).Last);
                              Measure_Str : constant String := Line (Fields (4).First .. Fields (4).Last);
                              Quanta_Str  : constant String := Line (Fields (5).First .. Fields (5).Last);
                              Q_Val       : constant Quanta_Type := Quanta_Type'Value (Quanta_Str);
                              Eff         : Effect;
                           begin
                              Eff.Key     := (Token => Make_Token (Key_Str));
                              Eff.Locus   := (Token => Make_Token (Locus_Str));
                              Eff.Measure := (Token => Make_Token (Measure_Str));
                              Eff.Amount  := Of_Quanta (Q_Val);

                              Curr_Effects.Count := Curr_Effects.Count + 1;
                              Curr_Effects.Values (Curr_Effects.Count) := Eff;
                           end;
                        else
                           Close (File);
                           return Set_Error (Result, Line_Num, "Unknown tag: " & Tag);
                        end if;
                     end;
                  end if;
               end if;
            end if;
         end;
      end loop;

      Flush_Current_Event;
      Close (File);

      Result.Success := True;
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Error parsing event memory file");
   end Read_Event_Memory_File;

end HRA_N.Storage.Event_Reader;
