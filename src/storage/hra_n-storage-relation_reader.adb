-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Relation_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Relation_Reader is

   Unit_Header : constant String := "LOAM-RELATION-UNIT-MEMORY" & ASCII.HT & "1";
   Discharge_Header : constant String :=
     "LOAM-RELATION-DISCHARGE-MEMORY" & ASCII.HT & "1";

   function Valid_Token_Field (Text : String) return Boolean is
   begin
      if Text'Length not in 1 .. Max_Token_Length then
         return False;
      end if;
      for C of Text loop
         if C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Token_Field;

   function Set_Unit_Error
     (Result   : in out Unit_Read_Result;
      Line_Num : Natural;
      Msg      : String) return Unit_Read_Result
   is
   begin
      Result.Success      := False;
      Result.Error_Line   := Line_Num;
      Result.Error_Len    := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Unit_Error;

   function Set_Discharge_Error
     (Result   : in out Discharge_Read_Result;
      Line_Num : Natural;
      Msg      : String) return Discharge_Read_Result
   is
   begin
      Result.Success      := False;
      Result.Error_Line   := Line_Num;
      Result.Error_Len    := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Discharge_Error;

   function Parse_Quanta
     (Text  : String;
      Value : out Quanta_Type) return Boolean
   is
   begin
      Value := Zero_Quanta;
      if Text'Length = 0 then
         return False;
      end if;
      begin
         Value := Quanta_Type'Value (Text);
         return True;
      exception
         when others =>
            return False;
      end;
   end Parse_Quanta;

   function Parse_Endpoint
     (Kind_Text     : String;
      Endpoint_Text : String;
      Endpoint      : out Relation_Endpoint) return Boolean
   is
   begin
      Endpoint := Household_Endpoint;
      if Kind_Text = "H" then
         return Endpoint_Text'Length = 0;
      elsif Kind_Text = "E" and then Valid_Token_Field (Endpoint_Text) then
         Endpoint := External_Endpoint (Make_Token (Endpoint_Text));
         return True;
      else
         return False;
      end if;
   end Parse_Endpoint;

   function Read_Relation_Unit_File (Path : String) return Unit_Read_Result is
      Result   : Unit_Read_Result;
      File     : File_Type;
      Line_Num : Natural := 0;
      Fields   : Field_Array;
      F_Count  : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Unit_Error (Result, 0, "Cannot open relation unit file: " & Path);
      end;

      if End_Of_File (File) then
         Close (File);
         return Set_Unit_Error (Result, 1, "Missing relation unit header");
      end if;

      Line_Num := 1;
      if Get_Line (File) /= Unit_Header then
         Close (File);
         return Set_Unit_Error (Result, Line_Num, "Invalid relation unit header");
      end if;

      while not End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, F_Count);
               if F_Count /= 9 then
                  Close (File);
                  return Set_Unit_Error
                    (Result, Line_Num, "Malformed RELATION row (expected 9 fields)");
               end if;

               declare
                  Marker : constant String := Line (Fields (1).First .. Fields (1).Last);
                  Rel_Id : constant String := Line (Fields (2).First .. Fields (2).Last);
                  Ev_Id  : constant String := Line (Fields (3).First .. Fields (3).Last);
                  Eff_Id : constant String := Line (Fields (4).First .. Fields (4).Last);
                  D_Kind : constant String := Line (Fields (5).First .. Fields (5).Last);
                  D_Tok  : constant String := Line (Fields (6).First .. Fields (6).Last);
                  C_Kind : constant String := Line (Fields (7).First .. Fields (7).Last);
                  C_Tok  : constant String := Line (Fields (8).First .. Fields (8).Last);
                  Q_Text : constant String := Line (Fields (9).First .. Fields (9).Last);
                  Debtor, Creditor : Relation_Endpoint;
                  Quantity : Quanta_Type;
               begin
                  if Marker /= "RELATION" then
                     Close (File);
                     return Set_Unit_Error (Result, Line_Num, "Expected RELATION row");
                  end if;
                  if not Valid_Token_Field (Rel_Id)
                    or else not Valid_Token_Field (Ev_Id)
                    or else not Valid_Token_Field (Eff_Id)
                  then
                     Close (File);
                     return Set_Unit_Error (Result, Line_Num, "Invalid relation identity token");
                  end if;
                  if not Parse_Endpoint (D_Kind, D_Tok, Debtor)
                    or else not Parse_Endpoint (C_Kind, C_Tok, Creditor)
                  then
                     Close (File);
                     return Set_Unit_Error (Result, Line_Num, "Invalid relation endpoint encoding");
                  end if;
                  if not Parse_Quanta (Q_Text, Quantity) then
                     Close (File);
                     return Set_Unit_Error (Result, Line_Num, "Invalid relation quantity");
                  end if;
                  if Result.Memory.Count = Max_Relation_Units then
                     Close (File);
                     return Set_Unit_Error (Result, Line_Num, "Relation unit memory full");
                  end if;

                  Result.Memory.Count := Result.Memory.Count + 1;
                  Result.Memory.Units (Result.Memory.Count) :=
                    (Id            => Make_Token (Rel_Id),
                     Source_Event  => (Token => Make_Token (Ev_Id)),
                     Source_Effect => (Token => Make_Token (Eff_Id)),
                     Debtor        => Debtor,
                     Creditor      => Creditor,
                     Quantity      => Quantity);
               end;
            end if;
         end;
      end loop;
      Close (File);
      Result.Success := True;
      return Result;
   end Read_Relation_Unit_File;

   function Read_Relation_Discharge_File
     (Path : String) return Discharge_Read_Result
   is
      Result   : Discharge_Read_Result;
      File     : File_Type;
      Line_Num : Natural := 0;
      Fields   : Field_Array;
      F_Count  : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Discharge_Error
              (Result, 0, "Cannot open relation discharge file: " & Path);
      end;

      if End_Of_File (File) then
         Close (File);
         return Set_Discharge_Error (Result, 1, "Missing relation discharge header");
      end if;

      Line_Num := 1;
      if Get_Line (File) /= Discharge_Header then
         Close (File);
         return Set_Discharge_Error (Result, Line_Num, "Invalid relation discharge header");
      end if;

      while not End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, F_Count);
               if F_Count /= 4 then
                  Close (File);
                  return Set_Discharge_Error
                    (Result, Line_Num, "Malformed DISCHARGE row (expected 4 fields)");
               end if;

               declare
                  Marker : constant String := Line (Fields (1).First .. Fields (1).Last);
                  Ev_Id  : constant String := Line (Fields (2).First .. Fields (2).Last);
                  Target : constant String := Line (Fields (3).First .. Fields (3).Last);
                  Q_Text : constant String := Line (Fields (4).First .. Fields (4).Last);
                  Quantity : Quanta_Type;
               begin
                  if Marker /= "DISCHARGE" then
                     Close (File);
                     return Set_Discharge_Error (Result, Line_Num, "Expected DISCHARGE row");
                  end if;
                  if not Valid_Token_Field (Ev_Id)
                    or else not Valid_Token_Field (Target)
                  then
                     Close (File);
                     return Set_Discharge_Error
                       (Result, Line_Num, "Invalid discharge identity token");
                  end if;
                  if not Parse_Quanta (Q_Text, Quantity) then
                     Close (File);
                     return Set_Discharge_Error (Result, Line_Num, "Invalid discharge quantity");
                  end if;
                  if Result.Memory.Count = Max_Relation_Discharges then
                     Close (File);
                     return Set_Discharge_Error
                       (Result, Line_Num, "Relation discharge memory full");
                  end if;

                  Result.Memory.Count := Result.Memory.Count + 1;
                  Result.Memory.Discharges (Result.Memory.Count) :=
                    (Event    => (Token => Make_Token (Ev_Id)),
                     Target   => Make_Token (Target),
                     Quantity => Quantity);
               end;
            end if;
         end;
      end loop;
      Close (File);
      Result.Success := True;
      return Result;
   end Read_Relation_Discharge_File;

end HRA_N.Storage.Relation_Reader;
