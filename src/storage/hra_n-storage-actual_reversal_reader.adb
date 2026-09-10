-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Actual_Reversal_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Actual_Reversal_Reader is

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

   function Read_Actual_Reversal_File (Path : String) return Read_Result is
      File        : File_Type;
      Result      : Read_Result;
      Line_Num    : Natural := 0;
      Header_Seen : Boolean := False;
      Fields      : Field_Array;
      Field_Count : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open actual reversal file: " & Path);
      end;

      while not End_Of_File (File) loop
         declare
            Line : constant String := Get_Line (File);
         begin
            Line_Num := Line_Num + 1;

            if Line'Length > 0 then
               Split_Tabs (Line, Fields, Field_Count);

               if not Header_Seen then
                  if Field_Count = 2
                    and then Line (Fields (1).First .. Fields (1).Last) = "LOAM-ACTUAL-REVERSAL-MEMORY"
                    and then Line (Fields (2).First .. Fields (2).Last) = "1"
                  then
                     Header_Seen := True;
                  else
                     Close (File);
                     return Set_Error (Result, Line_Num, "Invalid LOAM-ACTUAL-REVERSAL-MEMORY v1 header");
                  end if;
               else
                  if Field_Count = 3
                    and then Line (Fields (1).First .. Fields (1).Last) = "REVERSE"
                  then
                     declare
                        T_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                        R_Str : constant String := Line (Fields (3).First .. Fields (3).Last);
                     begin
                        if T_Str'Length = 0 or else T_Str'Length > Max_Token_Length then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Target token length invalid");
                        end if;

                        if R_Str'Length = 0 or else R_Str'Length > Max_Token_Length then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Reversal token length invalid");
                        end if;

                        if T_Str = R_Str then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Target and Reversal cannot be identical");
                        end if;

                        if Result.Memory.Count = Max_Reversals then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Exceeded maximum capacity of actual reversals");
                        end if;

                        declare
                           T_Tok : constant Token_Text := Make_Token (T_Str);
                           R_Tok : constant Token_Text := Make_Token (R_Str);
                           T_Id  : constant Event_Id   := (Token => T_Tok);
                           R_Id  : constant Event_Id   := (Token => R_Tok);
                        begin
                           if Is_Target_Reversed (Result.Memory, T_Id) then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Duplicate reversal target: " & T_Str);
                           end if;

                           Result.Memory.Count := Result.Memory.Count + 1;
                           Result.Memory.Entries (Result.Memory.Count) :=
                             (Target => T_Id, Reversal => R_Id);
                        end;
                     end;
                  else
                     Close (File);
                     return Set_Error (Result, Line_Num, "Malformed row in actual reversal memory");
                  end if;
               end if;
            end if;
         end;
      end loop;

      Close (File);

      if not Header_Seen then
         return Set_Error (Result, 0, "Missing LOAM-ACTUAL-REVERSAL-MEMORY header in empty file");
      end if;

      Result.Success := True;
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected I/O exception reading actual reversals");
   end Read_Actual_Reversal_File;

end HRA_N.Storage.Actual_Reversal_Reader;
