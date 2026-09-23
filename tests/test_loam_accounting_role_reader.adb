with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Test_Support; use Test_Support;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Accounting_Role_Reader;

package body Test_Loam_Accounting_Role_Reader is
   procedure Run is
      package Reader renames HRA_N.Storage.Loam_Accounting_Role_Reader;
      HT : constant String := [1 => ASCII.HT];
      NL : constant String := [1 => ASCII.LF];
      Header : constant String := "LOAM-ACCOUNTING-ROLE-MAP" & HT & "1" & NL;
      Missing : constant String := "/tmp/hra_n_missing_accounting_role.loam";
   begin
      if Ada.Directories.Exists (Missing) then
         Ada.Directories.Delete_File (Missing);
      end if;
      declare
         R : constant Reader.Read_Result := Reader.Read_File (Missing);
      begin
         Assert (not R.Success and then not R.Present and then R.Error_Len > 0,
                 "missing canonical AccountingRole is required evidence");
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content (Header);
      begin
         Assert (R.Success and then R.Present
                 and then Current_Entry_Count (R.Roles) = 0,
                 "header-only canonical AccountingRole is valid empty map");
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content
           (Header & "ROLE" & HT & "cash" & HT & "ASSET" & NL &
            "ROLE" & HT & "debt" & HT & "LIABILITY" & NL &
            "ROLE" & HT & "capital" & HT & "EQUITY" & NL &
            "ROLE" & HT & "salary" & HT & "INCOME" & NL &
            "ROLE" & HT & "food" & HT & "EXPENSE" & NL);
         Role : Accounting_Role;
         Found : Boolean;
      begin
         Assert (R.Success and then Current_Entry_Count (R.Roles) = 5,
                 "canonical current role map decodes exact five-role vocabulary");
         Find_Current_Role (R.Roles, (Token => Make_Token ("cash")), Role, Found);
         Assert (Found and then Role = Role_Asset,
                 "canonical current role lookup preserves vocabulary");
         Find_Current_Role (R.Roles, (Token => Make_Token ("missing")), Role, Found);
         Assert (not Found, "unassigned canonical locus remains unresolved");
      end;

      declare
         type Case_Array is array (Positive range <>) of Unbounded_String;
         Cases : constant Case_Array :=
           [To_Unbounded_String ("WRONG" & NL),
            To_Unbounded_String (Header & "ROLE" & HT & "cash" & NL),
            To_Unbounded_String
              (Header & "ROLE" & HT & "cash" & HT & "ASSET" & HT & "extra" & NL),
            To_Unbounded_String
              (Header & "ROLE" & HT & "bad" & ASCII.CR & HT & "ASSET" & NL),
            To_Unbounded_String
              (Header & "ROLE" & HT & "cash" & HT & "UNKNOWN" & NL),
            To_Unbounded_String
              (Header & "ROLE" & HT & "cash" & HT & "ASSET" & NL &
               "ROLE" & HT & "cash" & HT & "LIABILITY" & NL)];
      begin
         for I in Cases'Range loop
            declare
               R : constant Reader.Read_Result := Reader.Read_Content (To_String (Cases (I)));
            begin
               Assert (not R.Success and then R.Error_Len > 0,
                       "malformed canonical AccountingRole case" &
                       Positive'Image (I) & " rejects");
            end;
         end loop;
      end;

      declare
         Content : Unbounded_String := To_Unbounded_String (Header);
      begin
         for I in 1 .. Max_Role_Assignments + 1 loop
            Append (Content, "ROLE" & HT & "locus" & Integer'Image (I) &
                    HT & "ASSET" & NL);
         end loop;
         declare
            R : constant Reader.Read_Result := Reader.Read_Content (To_String (Content));
         begin
            Assert (not R.Success and then R.Error_Len > 0,
                    "canonical AccountingRole capacity overflow rejects");
         end;
      end;
   end Run;
end Test_Loam_Accounting_Role_Reader;
