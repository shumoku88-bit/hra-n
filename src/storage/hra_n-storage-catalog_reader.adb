-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Catalog_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Catalog_Reader is

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

   function Read_Catalog_File (Path : String) return Read_Result is
      Result   : Read_Result;
      File     : File_Type;
      Line_Num : Natural := 0;
      Fields   : Field_Array;
      F_Count  : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open catalog file: " & Path);
      end;

      while not End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, F_Count);

               if F_Count not in 2 .. 3 then
                  Close (File);
                  return Set_Error
                    (Result, Line_Num,
                     "Malformed catalog row (expected Id, Name [, Description])");
               end if;

               declare
                  Id_Str   : constant String := Line (Fields (1).First .. Fields (1).Last);
                  Name_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                  Desc_Str : constant String :=
                    (if F_Count = 3
                     then Line (Fields (3).First .. Fields (3).Last)
                     else "");
               begin
                  if Id_Str'Length = 0 then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Catalog identity cannot be empty");
                  end if;

                  if Id_Str'Length > Max_Token_Length then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Catalog identity too long: " & Id_Str);
                  end if;

                  if Name_Str'Length > Max_Token_Length then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Catalog display name too long");
                  end if;

                  if Desc_Str'Length > Max_Description_Length then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Catalog description too long");
                  end if;

                  if Has_Entry (Result.Catalog, Make_Token (Id_Str)) then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Duplicate catalog identity: " & Id_Str);
                  end if;

                  if Result.Catalog.Count = Max_Catalog_Entries then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Catalog memory full");
                  end if;

                  Result.Catalog.Count := Result.Catalog.Count + 1;
                  Result.Catalog.Entries (Result.Catalog.Count) :=
                    (Id           => Make_Token (Id_Str),
                     Display_Name => Make_Token (Name_Str),
                     Description  => Make_Description (Desc_Str));
               end;
            end if;
         end;
      end loop;
      Close (File);

      Result.Success := True;
      return Result;
   end Read_Catalog_File;

end HRA_N.Storage.Catalog_Reader;
