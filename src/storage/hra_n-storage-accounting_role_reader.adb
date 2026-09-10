-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Accounting_Role_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;

with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Accounting_Role_Reader is

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

   function Parse_Role (S : String; Role : out Accounting_Role) return Boolean is
   begin
      if S = "ASSET" then
         Role := Role_Asset;
         return True;
      elsif S = "LIABILITY" then
         Role := Role_Liability;
         return True;
      elsif S = "EQUITY" then
         Role := Role_Equity;
         return True;
      elsif S = "INCOME" then
         Role := Role_Income;
         return True;
      elsif S = "EXPENSE" then
         Role := Role_Expense;
         return True;
      else
         return False;
      end if;
   end Parse_Role;

   function Read_Accounting_Role_File (Path : String) return Read_Result is
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
            return Set_Error (Result, 0, "Cannot open accounting role file: " & Path);
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
                    and then Line (Fields (1).First .. Fields (1).Last) = "LOAM-ACCOUNTING-ROLE-MAP"
                    and then Line (Fields (2).First .. Fields (2).Last) = "1"
                  then
                     Header_Seen := True;
                  else
                     Close (File);
                     return Set_Error (Result, Line_Num, "Invalid LOAM-ACCOUNTING-ROLE-MAP v1 header");
                  end if;
               else
                  if Field_Count = 3
                    and then Line (Fields (1).First .. Fields (1).Last) = "ROLE"
                  then
                     declare
                        Locus_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                        Role_Str  : constant String := Line (Fields (3).First .. Fields (3).Last);
                        Parsed_R  : Accounting_Role;
                     begin
                        if Locus_Str'Length = 0 or else Locus_Str'Length > Max_Token_Length then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Locus token length invalid");
                        end if;

                        if not Parse_Role (Role_Str, Parsed_R) then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Unrecognized accounting role: " & Role_Str);
                        end if;

                        if Result.Map.Count = Max_Role_Assignments then
                           Close (File);
                           return Set_Error (Result, Line_Num, "Exceeded maximum capacity of role assignments");
                        end if;

                        declare
                           L_Tok : constant Token_Text := Make_Token (Locus_Str);
                           L_Id  : constant Locus_Id   := (Token => L_Tok);
                        begin
                           if Has_Role (Result.Map, L_Id) then
                              Close (File);
                              return Set_Error (Result, Line_Num, "Duplicate locus in role map: " & Locus_Str);
                           end if;

                           Result.Map.Count := Result.Map.Count + 1;
                           Result.Map.Entries (Result.Map.Count) :=
                             (Locus => L_Id, Role => Parsed_R);
                        end;
                     end;
                  else
                     Close (File);
                     return Set_Error (Result, Line_Num, "Malformed row in accounting role map");
                  end if;
               end if;
            end if;
         end;
      end loop;

      Close (File);

      if not Header_Seen then
         return Set_Error (Result, 0, "Missing LOAM-ACCOUNTING-ROLE-MAP header in empty file");
      end if;

      Result.Success := True;
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected I/O exception reading accounting roles");
   end Read_Accounting_Role_File;

end HRA_N.Storage.Accounting_Role_Reader;
