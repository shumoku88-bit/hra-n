-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Capacity_Reader
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Exact_File;

package body HRA_N.Storage.Loam_Capacity_Reader is

   use type Ada.Directories.File_Kind;

   package US renames Ada.Strings.Unbounded;

   Header : constant String :=
     "LOAM-NORMALIZED-CAPACITY" & ASCII.HT & "1";

   procedure Next_Line
     (Content  : String;
      Position : in out Natural;
      Line     : out US.Unbounded_String;
      Success  : out Boolean)
   is
      LF : Natural := 0;
   begin
      Line := US.Null_Unbounded_String;
      Success := False;

      if Content'Length = 0
        or else Position < Content'First
        or else Position > Content'Last
      then
         return;
      end if;

      for I in Position .. Content'Last loop
         if Content (I) = ASCII.LF then
            LF := I;
            exit;
         end if;
      end loop;

      if LF = 0 then
         return;
      elsif LF > Position then
         Line := US.To_Unbounded_String (Content (Position .. LF - 1));
      end if;

      Position := LF + 1;
      Success := True;
   end Next_Line;

   function Valid_Token (Text : String) return Boolean is
   begin
      if Text'Length = 0 or else Text'Length > Max_Token_Length then
         return False;
      end if;

      for C of Text loop
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

   type Field_Slice is record
      First : Positive;
      Last  : Natural;
   end record;

   type Field_Array is array (Positive range 1 .. 8) of Field_Slice;

   procedure Split_Tabs
     (Line   : String;
      Fields : out Field_Array;
      Count  : out Natural)
   is
      Start : Positive := Line'First;
   begin
      Count := 0;
      if Line'Length = 0 then
         return;
      end if;

      for I in Line'Range loop
         if Line (I) = ASCII.HT then
            if Count < Fields'Last then
               Count := Count + 1;
               Fields (Count) := (First => Start, Last => I - 1);
            end if;
            Start := I + 1;
         end if;
      end loop;

      if Count < Fields'Last then
         Count := Count + 1;
         Fields (Count) := (First => Start, Last => Line'Last);
      end if;
   end Split_Tabs;

   function Make_Failure
     (Status  : Capacity_Read_Status;
      At_Line : Natural;
      Message : String) return Read_Result
   is
      Result : Read_Result (Success => False);
      N      : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.Status     := Status;
      Result.Error_Line := At_Line;
      Result.Error_Len  := N;
      if N > 0 then
         Result.Error_Reason (1 .. N) :=
           Message (Message'First .. Message'First + N - 1);
      end if;
      return Result;
   end Make_Failure;

   function Read_Content (Content : String) return Read_Result is
      Result   : Read_Result (Success => True);
      Position : Natural :=
        (if Content'Length = 0 then 0 else Content'First);
      Line_No  : Natural := 0;

      function Fail
        (Status  : Capacity_Read_Status;
         At_Line : Natural;
         Message : String) return Read_Result is
      begin
         return Make_Failure (Status, At_Line, Message);
      end Fail;

   begin
      if Content'Length = 0 then
         return Fail (Document_Empty, 0, "LOAM capacity document is empty");
      elsif Content (Content'Last) /= ASCII.LF then
         return Fail (Missing_Final_Newline, 0, "LOAM capacity document does not end with LF");
      end if;

      declare
         Line    : US.Unbounded_String;
         Success : Boolean;
      begin
         Next_Line (Content, Position, Line, Success);
         if not Success then
            return Fail (Malformed_Header, 1, "Failed reading header line");
         end if;
         Line_No := 1;

         if US.To_String (Line) /= Header then
            return Fail (Malformed_Header, 1, "Invalid header: expected " & Header);
         end if;

         loop
            Next_Line (Content, Position, Line, Success);
            exit when not Success;
            Line_No := Line_No + 1;

            declare
               Raw : constant String := US.To_String (Line);
            begin
               if Raw'Length = 0 then
                  return Fail (Syntax_Error, Line_No, "Empty line encountered");
               end if;

               declare
                  Fields      : Field_Array;
                  Field_Count : Natural;
               begin
                  Split_Tabs (Raw, Fields, Field_Count);
                  if Field_Count = 0 then
                     return Fail (Syntax_Error, Line_No, "Blank line encountered");
                  end if;

                  declare
                     Tag : constant String :=
                       Raw (Fields (1).First .. Fields (1).Last);
                  begin
                     if Tag /= "MOVEMENT" then
                        return Fail (Syntax_Error, Line_No, "Expected MOVEMENT, got: " & Tag);
                     end if;

                     if Field_Count < 4 then
                        return Fail (Syntax_Error, Line_No, "Too few fields in MOVEMENT row");
                     end if;

                     declare
                        Id_Str   : constant String :=
                          Raw (Fields (2).First .. Fields (2).Last);
                        Date_Str : constant String :=
                          Raw (Fields (3).First .. Fields (3).Last);
                        Cur_Str  : constant String :=
                          Raw (Fields (4).First .. Fields (4).Last);
                        Parsed_D : Date_Type;
                        Mov      : Capacity_Movement := Empty_Capacity_Movement;
                        Eff      : Capacity_Effective;
                     begin
                        if not Valid_Token (Id_Str) then
                           return Fail (Syntax_Error, Line_No, "Invalid movement ID: " & Id_Str);
                        end if;
                        if not Parse_Iso_Date (Date_Str, Parsed_D) then
                           return Fail (Syntax_Error, Line_No, "Invalid date in MOVEMENT: " & Date_Str);
                        end if;
                        if not Valid_Token (Cur_Str) then
                           return Fail (Syntax_Error, Line_No, "Invalid currency: " & Cur_Str);
                        end if;

                        Mov.Id := Make_Token (Id_Str);
                        Mov.Currency := Make_Token (Cur_Str);
                        Eff :=
                          (Movement_Id => Make_Token (Id_Str),
                           Year        => Parsed_D.Year,
                           Month       => Parsed_D.Month,
                           Day         => Parsed_D.Day);

                        --  Read CHANGE rows until ENDMOVEMENT
                        loop
                           Next_Line (Content, Position, Line, Success);
                           if not Success then
                              return Fail (Syntax_Error, Line_No, "Unexpected EOF inside MOVEMENT block");
                           end if;
                           Line_No := Line_No + 1;

                           declare
                              Inner_Raw : constant String := US.To_String (Line);
                           begin
                              if Inner_Raw'Length = 0 then
                                 return Fail (Syntax_Error, Line_No, "Empty line inside MOVEMENT block");
                              end if;

                              declare
                                 Inner_Fields : Field_Array;
                                 Inner_Count  : Natural;
                              begin
                                 Split_Tabs (Inner_Raw, Inner_Fields, Inner_Count);
                                 if Inner_Count = 0 then
                                    return Fail (Syntax_Error, Line_No, "Blank line in MOVEMENT block");
                                 end if;

                                 declare
                                    Inner_Tag : constant String :=
                                      Inner_Raw (Inner_Fields (1).First .. Inner_Fields (1).Last);
                                 begin
                                    if Inner_Tag = "ENDMOVEMENT" then
                                       exit;
                                    elsif Inner_Tag = "CHANGE" then
                                       if Inner_Count < 3 then
                                          return Fail (Syntax_Error, Line_No, "Too few fields in CHANGE row");
                                       end if;

                                       declare
                                          Target_Kind : constant String :=
                                            Inner_Raw (Inner_Fields (2).First .. Inner_Fields (2).Last);
                                          Change_Rec  : Capacity_Change;
                                       begin
                                          if Target_Kind = "UNALLOCATED" then
                                             declare
                                                Amt_Str : constant String :=
                                                  Inner_Raw (Inner_Fields (3).First .. Inner_Fields (3).Last);
                                                Amt_Val : Quanta_Type;
                                             begin
                                                if not Parse_Quanta (Amt_Str, Amt_Val) then
                                                   return Fail (Syntax_Error, Line_No, "Invalid amount: " & Amt_Str);
                                                end if;
                                                Change_Rec :=
                                                  (Coord  => Make_Unallocated_Coordinate,
                                                   Amount => Amt_Val);
                                             end;
                                          elsif Target_Kind = "PURPOSE" then
                                             if Inner_Count < 4 then
                                                return Fail (Syntax_Error, Line_No, "PURPOSE change requires purpose name and amount");
                                             end if;
                                             declare
                                                Purp_Str : constant String :=
                                                  Inner_Raw (Inner_Fields (3).First .. Inner_Fields (3).Last);
                                                Amt_Str  : constant String :=
                                                  Inner_Raw (Inner_Fields (4).First .. Inner_Fields (4).Last);
                                                Amt_Val  : Quanta_Type;
                                             begin
                                                if not Valid_Token (Purp_Str) then
                                                   return Fail (Syntax_Error, Line_No, "Invalid purpose token: " & Purp_Str);
                                                end if;
                                                if not Parse_Quanta (Amt_Str, Amt_Val) then
                                                   return Fail (Syntax_Error, Line_No, "Invalid amount: " & Amt_Str);
                                                end if;
                                                Change_Rec :=
                                                  (Coord  => Make_Purpose_Coordinate (Make_Token (Purp_Str)),
                                                   Amount => Amt_Val);
                                             end;
                                          else
                                             return Fail (Syntax_Error, Line_No, "Unknown CHANGE coordinate kind: " & Target_Kind);
                                          end if;

                                          if Mov.Change_Count = Max_Changes_Per_Movement then
                                             return Fail (Capacity_Exceeded, Line_No, "Exceeded maximum changes per movement");
                                          end if;
                                          Mov.Change_Count := Mov.Change_Count + 1;
                                          Mov.Changes (Mov.Change_Count) := Change_Rec;
                                       end;
                                    else
                                       return Fail (Syntax_Error, Line_No, "Expected CHANGE or ENDMOVEMENT, got: " & Inner_Tag);
                                    end if;
                                 end;
                              end;
                           end;
                        end loop;

                        --  Conservation check: strictly Delta = 0
                        if not Is_Conserved (Mov) then
                           return Fail (Unconserved_Movement, Line_No, "Capacity movement is not conserved (Delta /= 0)");
                        end if;

                        if Result.Capacity.Movement_Count = Max_Capacity_Movements then
                           return Fail (Capacity_Exceeded, Line_No, "Exceeded maximum capacity movements");
                        end if;

                        Result.Capacity.Movement_Count := Result.Capacity.Movement_Count + 1;
                        Result.Capacity.Movements (Result.Capacity.Movement_Count) := Mov;

                        Result.Capacity.Effective_Count := Result.Capacity.Effective_Count + 1;
                        Result.Capacity.Effective (Result.Capacity.Effective_Count) := Eff;
                     end;
                  end;
               end;
            end;
         end loop;
      end;

      return Result;
   exception
      when others =>
         return Fail (Syntax_Error, Line_No, "unexpected LOAM capacity reader failure");
   end Read_Content;

   function Read_File (Path : String) return Read_Result is
      Msg : constant String := "required LOAM capacity file is missing or unreadable";
   begin
      if not Ada.Directories.Exists (Path) then
         return Make_Failure (IO_Error, 0, Msg);
      end if;
      if Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         return Make_Failure (IO_Error, 0, Msg);
      end if;
      declare
         Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Path);
      begin
         if not Exact.Success then
            return Make_Failure (IO_Error, 0, Msg);
         end if;
         return Read_Content (US.To_String (Exact.Content));
      end;
   exception
      when others =>
         return Make_Failure (IO_Error, 0, Msg);
   end Read_File;

   function Format_Error (Result : Read_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Document_Empty        => return "LOAM capacity document is empty";
            when Missing_Final_Newline => return "LOAM capacity document does not end with LF";
            when Malformed_Header      => return "malformed LOAM capacity header";
            when Syntax_Error          => return "syntax error in LOAM capacity document";
            when Unconserved_Movement  => return "capacity movement is not conserved";
            when Capacity_Exceeded     => return "exceeded maximum capacity movements or changes";
            when IO_Error              => return "I/O error reading LOAM capacity document";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Capacity_Reader;
