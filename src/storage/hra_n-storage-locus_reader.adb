-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Locus_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;      use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Locus_Reader is

   type Field_Slice is record
      First : Positive;
      Last  : Natural;
   end record;

   type Field_Array is array (1 .. 4) of Field_Slice;

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
     (Result   : in out Read_Locus_Result;
      Line_Num : Natural;
      Msg      : String) return Read_Locus_Result
   is
   begin
      Result.Success      := False;
      Result.Error_Line   := Line_Num;
      Result.Error_Len    := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Error;

   function Read_Locus_File (Path : String) return Read_Locus_Result is
      Result   : Read_Locus_Result;
      File     : File_Type;
      Line_Num : Natural := 0;
      Loci     : Locus_Array := [others => (Token => (Length => 0, Value => [others => ' ']))];
      Count    : Natural := 0;

      Header_Expected : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1";
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

            if Line_Num = 1 then
               if Line /= Header_Expected then
                  Close (File);
                  return Set_Error (Result, 1, "Invalid header: expected " & Header_Expected);
               end if;
            elsif Line'Length > 0 then
               declare
                  Fields : Field_Array;
                  F_Cnt  : Natural;
               begin
                  Split_Tabs (Line, Fields, F_Cnt);

                  if F_Cnt /= 2 then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Malformed row: expected 2 fields");
                  end if;

                  declare
                     Tag_Str   : constant String := Line (Fields (1).First .. Fields (1).Last);
                     Locus_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                  begin
                     if Tag_Str /= "LOCUS" then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Unknown tag: " & Tag_Str);
                     end if;

                     if Locus_Str'Length > Max_Token_Length then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Token too long: " & Locus_Str);
                     end if;

                     if Count = Max_Admitted_Loci then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Capacity exceeded");
                     end if;

                     Count := Count + 1;
                     Loci (Count) := (Token => Make_Token (Locus_Str));
                  end;
               end;
            end if;
         end;
      end loop;

      Close (File);

      if Line_Num = 0 then
         return Set_Error (Result, 0, "Empty file");
      end if;

      Result.Success    := True;
      Result.Vocabulary := Make_Vocabulary (Loci, Count);
      return Result;

   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected exception during read");
   end Read_Locus_File;

end HRA_N.Storage.Locus_Reader;
