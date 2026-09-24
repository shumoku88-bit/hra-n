-------------------------------------------------------------------------------
--  HRA-N: read-only LOAM current AccountingRole authority bridge
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Exact_File;

package body HRA_N.Storage.Loam_Accounting_Role_Reader is

   use type Ada.Directories.File_Kind;
   package US renames Ada.Strings.Unbounded;

   Header : constant String := "LOAM-ACCOUNTING-ROLE-MAP" & ASCII.HT & "1";

   function Make_Failure
     (Status  : Role_Read_Status;
      At_Line : Natural;
      Message : String;
      Present : Boolean := True) return Read_Result
   is
      Result : Read_Result (Success => False);
      N      : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.Present    := Present;
      Result.Status     := Status;
      Result.Error_Line := At_Line;
      Result.Error_Len  := N;
      if N > 0 then
         Result.Error_Reason (1 .. N) :=
           Message (Message'First .. Message'First + N - 1);
      end if;
      return Result;
   end Make_Failure;

   procedure Next_Line
     (Content  : String;
      Position : in out Natural;
      Line     : out US.Unbounded_String;
      Success  : out Boolean)
   is
      LF : Natural := 0;
   begin
      Line := US.Null_Unbounded_String;
      Success := False;
      if Content'Length = 0
        or else Position < Content'First
        or else Position > Content'Last
      then
         return;
      end if;
      for I in Position .. Content'Last loop
         if Content (I) = ASCII.LF then
            LF := I;
            exit;
         end if;
      end loop;
      if LF = 0 then
         return;
      elsif LF > Position then
         Line := US.To_Unbounded_String (Content (Position .. LF - 1));
      end if;
      Position := LF + 1;
      Success := True;
   end Next_Line;

   function Valid_Token (Text : String) return Boolean is
   begin
      if Text'Length = 0 or else Text'Length > Max_Token_Length then
         return False;
      end if;
      for C of Text loop
         if C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Token;

   function Decode_Role
     (Text  : String;
      Role  : out Accounting_Role) return Boolean
   is
   begin
      if Text = "ASSET" then
         Role := Role_Asset;
      elsif Text = "LIABILITY" then
         Role := Role_Liability;
      elsif Text = "EQUITY" then
         Role := Role_Equity;
      elsif Text = "INCOME" then
         Role := Role_Income;
      elsif Text = "EXPENSE" then
         Role := Role_Expense;
      else
         Role := Role_Asset;
         return False;
      end if;
      return True;
   end Decode_Role;

   function Read_Content (Content : String) return Read_Result is
      Result   : Read_Result (Success => True);
      Items    : Current_Role_List;
      Position : Natural := (if Content'Length = 0 then 0 else Content'First);
      Line_No  : Natural := 0;

      function Fail
        (Status  : Role_Read_Status;
         At_Line : Natural;
         Message : String) return Read_Result is
      begin
         return Make_Failure (Status, At_Line, Message, Present => True);
      end Fail;

   begin
      Result.Present := True;
      if Content'Length = 0 then
         return Fail (Document_Empty, 0, "LOAM AccountingRole document is empty");
      elsif Content (Content'Last) /= ASCII.LF then
         return Fail (Missing_Final_Newline, 0, "LOAM AccountingRole document must end with newline");
      end if;

      declare
         First : US.Unbounded_String;
         Have_Line : Boolean;
      begin
         Next_Line (Content, Position, First, Have_Line);
         if not Have_Line or else US.To_String (First) /= Header then
            return Fail (Unsupported_Header, 1, "unsupported LOAM AccountingRole header");
         end if;
         Line_No := 1;
      end;

      while Position <= Content'Last loop
         declare
            Raw : US.Unbounded_String;
            Have_Line : Boolean;
         begin
            Next_Line (Content, Position, Raw, Have_Line);
            Line_No := Line_No + 1;
            if not Have_Line then
               return Fail (Syntax_Error, Line_No, "unterminated ROLE row");
            end if;
            declare
               Line       : constant String := US.To_String (Raw);
               First_Tab  : Natural := 0;
               Second_Tab : Natural := 0;
               Extra_Tab  : Boolean := False;
            begin
               for I in Line'Range loop
                  if Line (I) = ASCII.HT then
                     if First_Tab = 0 then
                        First_Tab := I;
                     elsif Second_Tab = 0 then
                        Second_Tab := I;
                     else
                        Extra_Tab := True;
                     end if;
                  end if;
               end loop;
               if First_Tab = 0
                 or else Second_Tab = 0
                 or else Extra_Tab
                 or else First_Tab <= Line'First
                 or else Line (Line'First .. First_Tab - 1) /= "ROLE"
                 or else Second_Tab = Line'Last
               then
                  return Fail (Syntax_Error, Line_No, "expected ROLE locus role row");
               end if;

               declare
                  Locus_Text : constant String :=
                    Line (First_Tab + 1 .. Second_Tab - 1);
                  Role_Text : constant String :=
                    Line (Second_Tab + 1 .. Line'Last);
                  Role : Accounting_Role;
                  Candidate : Current_Role_Assignment;
               begin
                  if not Valid_Token (Locus_Text) then
                     return Fail (Invalid_Token, Line_No, "invalid LOAM AccountingRole locus token");
                  elsif not Decode_Role (Role_Text, Role) then
                     return Fail (Unknown_Vocabulary, Line_No, "unknown LOAM AccountingRole vocabulary");
                  elsif Items.Count = Max_Role_Assignments then
                     return Fail (Capacity_Exceeded, Line_No, "HRA-N current AccountingRole capacity exceeded");
                  end if;

                  Candidate :=
                    (Locus => (Token => Make_Token (Locus_Text)), Role => Role);
                  for I in 1 .. Items.Count loop
                     if Equal_Token
                       (Items.Entries (I).Locus.Token, Candidate.Locus.Token)
                     then
                        return Fail (Duplicate_Locus, Line_No, "duplicate LOAM AccountingRole locus");
                     end if;
                  end loop;
                  Items.Count := Items.Count + 1;
                  Items.Entries (Items.Count) := Candidate;
               end;
            end;
         end;
      end loop;

      if not Current_Loci_Are_Unique (Items) then
         return Fail (Duplicate_Locus, Line_No, "duplicate LOAM AccountingRole locus");
      end if;
      Result.Roles := Make_Current_Role_Map (Items);
      Result.Present := True;
      return Result;
   exception
      when others =>
         return Fail (Syntax_Error, Line_No, "unexpected LOAM AccountingRole reader failure");
   end Read_Content;

   function Read_File (Path : String) return Read_Result is
      Msg : constant String := "required LOAM AccountingRole file is missing or unreadable";
   begin
      if not Ada.Directories.Exists (Path) then
         return Make_Failure (IO_Error, 0, Msg, Present => False);
      end if;
      if Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         return Make_Failure (IO_Error, 0, Msg, Present => True);
      end if;
      declare
         Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Path);
      begin
         if not Exact.Success then
            return Make_Failure (IO_Error, 0, Msg, Present => True);
         end if;
         return Read_Content (US.To_String (Exact.Content));
      end;
   exception
      when others =>
         return Make_Failure (IO_Error, 0, Msg, Present => False);
   end Read_File;

   function Format_Error (Result : Read_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Document_Empty        => return "LOAM AccountingRole document is empty";
            when Missing_Final_Newline => return "LOAM AccountingRole document must end with newline";
            when Unsupported_Header    => return "unsupported LOAM AccountingRole header";
            when Syntax_Error          => return "syntax error in LOAM AccountingRole document";
            when Invalid_Token         => return "invalid LOAM AccountingRole locus token";
            when Unknown_Vocabulary    => return "unknown LOAM AccountingRole vocabulary";
            when Capacity_Exceeded     => return "HRA-N current AccountingRole capacity exceeded";
            when Duplicate_Locus       => return "duplicate LOAM AccountingRole locus";
            when IO_Error              => return "required LOAM AccountingRole file is missing or unreadable";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Accounting_Role_Reader;
