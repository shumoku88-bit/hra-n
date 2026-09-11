-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Journal_Writer
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

package body HRA_N.Storage.Journal_Writer is

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
      Buf    : Unbounded_String;

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

      --  Build line
      Append (Buf, "TX ");
      Append (Buf, Tx_Id);
      Append (Buf, " ");
      Append (Buf, Format_Iso_Date (Valid_On));

      for I in 1 .. Effects.Count loop
         declare
            Eff : constant Effect := Effects.Values (I);
            Loc : constant String := Eff.Locus.Token.Value (1 .. Eff.Locus.Token.Length);
            Mea : constant String := Eff.Measure.Token.Value (1 .. Eff.Measure.Token.Length);
            Amt : constant String := Long_Long_Integer'Image (Long_Long_Integer (Eff.Amount.Quanta));
            -- Strip leading space from Image
            Amt_Trimmed : constant String :=
              (if Amt'Length > 0 and then Amt (Amt'First) = ' '
               then Amt (Amt'First + 1 .. Amt'Last)
               else Amt);
         begin
            Append (Buf, " ");
            Append (Buf, Loc);
            Append (Buf, ":");
            Append (Buf, Amt_Trimmed);
            if Mea /= "jpy" then
               Append (Buf, ":");
               Append (Buf, Mea);
            end if;
         end;
      end loop;

      if Purpose'Length > 0 then
         Append (Buf, " @");
         Append (Buf, Purpose);
      end if;

      if Description'Length > 0 then
         Append (Buf, " """);
         Append (Buf, Description);
         Append (Buf, """");
      end if;

      if Replaces_Id'Length > 0 then
         Append (Buf, " replaces:");
         Append (Buf, Replaces_Id);
      end if;

      if Relation_Str'Length > 0 then
         Append (Buf, " relation:");
         Append (Buf, Relation_Str);
      end if;

      if Discharge_Str'Length > 0 then
         Append (Buf, " discharges:");
         Append (Buf, Discharge_Str);
      end if;

      --  Append to file
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

      Ada.Text_IO.Put_Line (File, To_String (Buf));
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

end HRA_N.Storage.Journal_Writer;
