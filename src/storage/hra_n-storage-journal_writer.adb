with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

package body HRA_N.Storage.Journal_Writer is

   function Encode_Transaction
     (Tx_Id         : String;
      Valid_On      : Date_Type;
      Effects       : Effect_List;
      Purpose       : String := "";
      Description   : String := "";
      Replaces_Id   : String := "";
      Relation_Str  : String := "";
      Discharge_Str : String := "") return String
   is
      Buf : Unbounded_String;
   begin
      Append (Buf, "TX " & Tx_Id & " " & Format_Iso_Date (Valid_On));
      for I in 1 .. Effects.Count loop
         declare
            Eff : constant Effect := Effects.Values (I);
            Loc : constant String := Eff.Locus.Token.Value (1 .. Eff.Locus.Token.Length);
            Mea : constant String := Eff.Measure.Token.Value (1 .. Eff.Measure.Token.Length);
            Amt : constant String := Trim
              (Long_Long_Integer'Image (Long_Long_Integer (Eff.Amount.Quanta)),
               Ada.Strings.Both);
         begin
            Append (Buf, " " & Loc & ":" & Amt);
            if Mea /= "jpy" then
               Append (Buf, ":" & Mea);
            end if;
         end;
      end loop;
      if Purpose'Length > 0 then
         Append (Buf, " @" & Purpose);
      end if;
      if Description'Length > 0 then
         Append (Buf, " """ & Description & """");
      end if;
      if Replaces_Id'Length > 0 then
         Append (Buf, " replaces:" & Replaces_Id);
      end if;
      if Relation_Str'Length > 0 then
         Append (Buf, " relation:" & Relation_Str);
      end if;
      if Discharge_Str'Length > 0 then
         Append (Buf, " discharges:" & Discharge_Str);
      end if;
      return To_String (Buf);
   end Encode_Transaction;

   function Append_Transaction
     (Journal_Path : String;
      Tx_Id        : String;
      Valid_On     : Date_Type;
      Effects      : Effect_List;
      Purpose      : String := "";
      Description  : String := "";
      Replaces_Id  : String := "";
      Relation_Str : String := "";
      Discharge_Str : String := "") return Append_Result
   is
      File   : Ada.Text_IO.File_Type;
      Result : Append_Result;

      procedure Set_Error (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Len := L;
         Result.Error_Reason (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Set_Error;
   begin
      if Index (Journal_Path, "/.hra/generations/") /= 0 then
         Set_Error ("Selected generations are immutable; use an authority transaction");
         return Result;
      end if;

      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.Append_File, Journal_Path);
      exception
         when others =>
            begin
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Journal_Path);
            exception
               when others =>
                  Set_Error ("Cannot open or create journal file: " & Journal_Path);
                  return Result;
            end;
      end;

      Ada.Text_IO.Put_Line
        (File,
         Encode_Transaction
           (Tx_Id, Valid_On, Effects, Purpose, Description, Replaces_Id,
            Relation_Str, Discharge_Str));
      Ada.Text_IO.Close (File);
      Result.Success := True;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Set_Error ("Unexpected I/O error appending to journal");
         return Result;
   end Append_Transaction;

   function Encode_Assertion
     (As_Id       : String;
      Valid_On    : Date_Type;
      Locus       : String;
      Measure     : String;
      Amount      : Quanta_Type;
      Description : String := "") return String
   is
      Amt_Str   : constant String := Trim (Amount'Image, Ada.Strings.Both);
      Coord_Str : constant String :=
        (if Measure = "jpy" then Locus else Locus & ":" & Measure);
      Desc_Part : constant String :=
        (if Description'Length > 0 then " """ & Description & """" else "");
   begin
      return "ASSERT " & As_Id & " " & Format_Iso_Date (Valid_On) & " " &
             Coord_Str & " " & Amt_Str & Desc_Part;
   end Encode_Assertion;

end HRA_N.Storage.Journal_Writer;
