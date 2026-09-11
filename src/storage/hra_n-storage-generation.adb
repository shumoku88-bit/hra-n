with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO;

package body HRA_N.Storage.Generation is

   function Identity_String (Selection : Selection_Result) return String is
     (Selection.Identity (1 .. Selection.Id_Len));

   function Valid_Identity (Value : String) return Boolean is
   begin
      if Value'Length = 0 or else Value'Length > Max_Snapshot_Id_Length then
         return False;
      end if;
      for Ch of Value loop
         if Ch not in 'a' .. 'z'
           and then Ch not in '0' .. '9'
           and then Ch /= '-'
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Identity;

   function Read_Selection (Base_Dir : String) return Selection_Result is
      Result   : Selection_Result;
      Selector : constant String := Base_Dir & "/.hra/CURRENT";
      File     : Ada.Text_IO.File_Type;

      procedure Set_Error (Message : String) is
         Len : constant Natural := Natural'Min (Message'Length, Result.Error'Length);
      begin
         Result.Success := False;
         Result.Error_Len := Len;
         Result.Error (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Error;
   begin
      if not Ada.Directories.Exists (Selector) then
         Result.Success := True;
         Result.Found := False;
         return Result;
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Selector);
      declare
         Selected  : constant String := Ada.Text_IO.Get_Line (File);
         Extra_Row : constant Boolean := not Ada.Text_IO.End_Of_File (File);
      begin
         Ada.Text_IO.Close (File);
         if Extra_Row then
            Set_Error (".hra/CURRENT must contain exactly one identity row");
         elsif not Valid_Identity (Selected) then
            Set_Error ("invalid snapshot identity in .hra/CURRENT");
         else
            Result.Success := True;
            Result.Found := True;
            Result.Id_Len := Selected'Length;
            Result.Identity (1 .. Result.Id_Len) := Selected;
         end if;
      end;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Set_Error ("cannot read .hra/CURRENT");
         return Result;
   end Read_Selection;

   function Next_Identity
     (Current : String;
      Next    : out String;
      Length  : out Natural) return Boolean
   is
      Number : Natural := 0;
   begin
      Next := [others => ' '];
      Length := 0;
      if Current'Length /= 9 or else Current (Current'First) /= 'g'
        or else Next'Length < 9
      then
         return False;
      end if;

      for Index in Current'First + 1 .. Current'Last loop
         if Current (Index) not in '0' .. '9' then
            return False;
         end if;
         Number := Number * 10 +
           Character'Pos (Current (Index)) - Character'Pos ('0');
      end loop;
      if Number >= 99_999_999 then
         return False;
      end if;

      declare
         Image_Text : constant String :=
           Trim (Natural'Image (Number + 1), Ada.Strings.Both);
         Value : constant String :=
           "g" & (1 .. 8 - Image_Text'Length => '0') & Image_Text;
      begin
         Next (Next'First .. Next'First + 8) := Value;
         Length := 9;
      end;
      return True;
   exception
      when others =>
         Next := [others => ' '];
         Length := 0;
         return False;
   end Next_Identity;

end HRA_N.Storage.Generation;
