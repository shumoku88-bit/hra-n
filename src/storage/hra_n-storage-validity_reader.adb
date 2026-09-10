-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Validity_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Application.Actual_Validity_Frontier; use HRA_N.Application.Actual_Validity_Frontier;

with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Validity_Reader is

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
      History     : Validity_History;
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

                           if History.Fact_Count = Max_Validity_Facts then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Too many validity facts");
                           end if;

                           declare
                              Ev_Str   : constant String := Line (Fields (2).First .. Fields (2).Last);
                              Date_Str : constant String := Line (Fields (3).First .. Fields (3).Last);
                              Parsed_D : Date_Type;
                              Ev_Id    : constant Event_Id := (Token => Make_Token (Ev_Str));
                           begin
                              if not Parse_Iso_Date (Date_Str, Parsed_D) then
                                 Close (File);
                                 return Set_Error (Result, Line_Num, "Invalid calendar date: " & Date_Str);
                              end if;

                              History.Fact_Count := History.Fact_Count + 1;
                              History.Facts (History.Fact_Count) :=
                                (Id       => Root_Fact_Id (Ev_Id),
                                 Event_Id => Ev_Id,
                                 Valid_On => Parsed_D);
                           end;
                        elsif Tag = "REVISION" then
                           if Field_Count /= 4 then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Malformed REVISION row (expected 4 fields)");
                           end if;

                           if History.Fact_Count = Max_Validity_Facts then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Too many validity facts");
                           end if;

                           declare
                              Fact_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                              Ev_Str   : constant String := Line (Fields (3).First .. Fields (3).Last);
                              Date_Str : constant String := Line (Fields (4).First .. Fields (4).Last);
                              Parsed_D : Date_Type;
                           begin
                              if not Parse_Iso_Date (Date_Str, Parsed_D) then
                                 Close (File);
                                 return Set_Error (Result, Line_Num, "Invalid calendar date: " & Date_Str);
                              end if;

                              History.Fact_Count := History.Fact_Count + 1;
                              History.Facts (History.Fact_Count) :=
                                (Id       => (Token => Make_Token (Fact_Str)),
                                 Event_Id => (Token => Make_Token (Ev_Str)),
                                 Valid_On => Parsed_D);
                           end;
                        elsif Tag = "CORRECTION" then
                           if Field_Count /= 5 then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Malformed CORRECTION row (expected 5 fields)");
                           end if;

                           if History.Correction_Count = Max_Validity_Corrections then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Too many validity corrections");
                           end if;

                           declare
                              Corr_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                              Kind_Str : constant String := Line (Fields (3).First .. Fields (3).Last);
                              Targ_Str : constant String := Line (Fields (4).First .. Fields (4).Last);
                              Repl_Str : constant String := Line (Fields (5).First .. Fields (5).Last);
                              Target_Id : Validity_Fact_Id;
                           begin
                              if Kind_Str = "ROOT" then
                                 Target_Id := Root_Fact_Id ((Token => Make_Token (Targ_Str)));
                              elsif Kind_Str = "REVISION" then
                                 Target_Id := (Token => Make_Token (Targ_Str));
                              else
                                 Close (File);
                                 return Set_Error (Result, Line_Num, "Unknown CORRECTION kind: " & Kind_Str);
                              end if;

                              History.Correction_Count := History.Correction_Count + 1;
                              History.Corrections (History.Correction_Count) :=
                                (Id          => (Token => Make_Token (Corr_Str)),
                                 Target      => Target_Id,
                                 Replacement => (Token => Make_Token (Repl_Str)));
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

      if not Project_Memory (History, Result.Memory) then
         return Set_Error (Result, Line_Num, "Admitted actual-validity frontier failed closed");
      end if;

      Result.History := History;
      Result.Success := True;
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected error reading validity file");
   end Read_Validity_File;

   function Format_Validity_History (History : Validity_History) return String is
      function Is_Replacement (Id : Validity_Fact_Id) return Boolean is
      begin
         for C in 1 .. History.Correction_Count loop
            if Equal_Token (History.Corrections (C).Replacement.Token, Id.Token) then
               return True;
            end if;
         end loop;
         return False;
      end Is_Replacement;

      Res : Unbounded_String :=
        To_Unbounded_String ("LOAM-ACTUAL-VALIDITY-HISTORY" & ASCII.HT & "2" & ASCII.LF);
   begin
      for I in 1 .. History.Fact_Count loop
         declare
            F        : constant Validity_Fact := History.Facts (I);
            Ev_Str   : constant String := F.Event_Id.Token.Value (1 .. F.Event_Id.Token.Length);
            Date_Str : constant String := Format_Iso_Date (F.Valid_On);
         begin
            if Is_Replacement (F.Id) then
               declare
                  Id_Str : constant String := F.Id.Token.Value (1 .. F.Id.Token.Length);
               begin
                  Append (Res, "REVISION" & ASCII.HT & Id_Str & ASCII.HT & Ev_Str & ASCII.HT & Date_Str & ASCII.LF);
               end;
            else
               Append (Res, "BASE" & ASCII.HT & Ev_Str & ASCII.HT & Date_Str & ASCII.LF);
            end if;
         end;
      end loop;

      for I in 1 .. History.Correction_Count loop
         declare
            C        : constant Validity_Correction := History.Corrections (I);
            C_Id_Str : constant String := C.Id.Token.Value (1 .. C.Id.Token.Length);
            Repl_Str : constant String := C.Replacement.Token.Value (1 .. C.Replacement.Token.Length);
            T_Fact   : Validity_Fact;
            Found_T  : Boolean;
         begin
            Find_Fact_By_Id (History, C.Target, T_Fact, Found_T);
            if Found_T and then Is_Root_Fact (T_Fact) then
               declare
                  Ev_Str : constant String := T_Fact.Event_Id.Token.Value (1 .. T_Fact.Event_Id.Token.Length);
               begin
                  Append (Res, "CORRECTION" & ASCII.HT & C_Id_Str & ASCII.HT & "ROOT" & ASCII.HT & Ev_Str & ASCII.HT & Repl_Str & ASCII.LF);
               end;
            else
               declare
                  Targ_Str : constant String := C.Target.Token.Value (1 .. C.Target.Token.Length);
               begin
                  Append (Res, "CORRECTION" & ASCII.HT & C_Id_Str & ASCII.HT & "REVISION" & ASCII.HT & Targ_Str & ASCII.HT & Repl_Str & ASCII.LF);
               end;
            end if;
         end;
      end loop;

      return To_String (Res);
   end Format_Validity_History;

end HRA_N.Storage.Validity_Reader;
