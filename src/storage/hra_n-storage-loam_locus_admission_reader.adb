-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Locus_Admission_Reader
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Exact_File;

package body HRA_N.Storage.Loam_Locus_Admission_Reader is

   package US renames Ada.Strings.Unbounded;

   Header : constant String :=
     "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1";

   function Make_Failure
     (Status  : Locus_Read_Status;
      At_Line : Natural;
      Message : String) return Read_Result
   is
      Result : Read_Result (Success => False);
      N      : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
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

   function Read_Content (Content : String) return Read_Result is
      Result   : Read_Result (Success => True);
      Loci     : Locus_Array;
      Count    : Locus_Count_Type := 0;
      Position : Natural :=
        (if Content'Length = 0 then 0 else Content'First);
      Line_No  : Natural := 0;

      function Fail
        (Status  : Locus_Read_Status;
         At_Line : Natural;
         Message : String) return Read_Result is
      begin
         return Make_Failure (Status, At_Line, Message);
      end Fail;

   begin
      if Content'Length = 0 then
         return Fail (Document_Empty, 0, "LOAM Locus admission document is empty");
      elsif Content (Content'Last) /= ASCII.LF then
         return Fail
           (Missing_Final_Newline, 0, "LOAM Locus admission document must end with newline");
      end if;

      declare
         First     : US.Unbounded_String;
         Have_Line : Boolean;
      begin
         Next_Line (Content, Position, First, Have_Line);
         if not Have_Line then
            return Fail (Document_Empty, 0, "LOAM Locus admission document is empty");
         end if;
         Line_No := 1;
         if US.To_String (First) /= Header then
            return Fail (Unsupported_Header, 1, "unsupported LOAM Locus admission header");
         end if;
      end;

      while Position <= Content'Last loop
         declare
            Raw       : US.Unbounded_String;
            Have_Line : Boolean;
         begin
            Next_Line (Content, Position, Raw, Have_Line);
            if not Have_Line then
               return Fail (Syntax_Error, Line_No + 1, "unterminated LOCUS row");
            end if;
            Line_No := Line_No + 1;

            declare
               Line : constant String := US.To_String (Raw);
            begin
               if Line'Length <= 6
                 or else Line (Line'First .. Line'First + 4) /= "LOCUS"
                 or else Line (Line'First + 5) /= ASCII.HT
               then
                  return Fail (Syntax_Error, Line_No, "expected LOCUS row");
               end if;

               declare
                  Token : constant String :=
                    Line (Line'First + 6 .. Line'Last);
               begin
                  if not Valid_Token (Token) then
                     return Fail (Invalid_Token, Line_No, "invalid LOAM Locus token");
                  elsif Count = Max_Admitted_Loci then
                     return Fail
                       (Capacity_Exceeded, Line_No, "HRA-N Locus admission capacity exceeded");
                  end if;

                  for I in 1 .. Count loop
                     if Equal_Token
                       (Loci (I).Token, Make_Token (Token))
                     then
                        return Fail
                          (Duplicate_Token, Line_No, "duplicate LOAM Locus admission token");
                     end if;
                  end loop;

                  Count := Count + 1;
                  Loci (Count) := (Token => Make_Token (Token));
               end;
            end;
         end;
      end loop;

      Result.Vocabulary := Make_Vocabulary (Loci, Count);
      if not Loci_Are_Unique (Result.Vocabulary) then
         return Fail
           (Duplicate_Token, Line_No, "duplicate LOAM Locus admission token");
      end if;

      return Result;

   exception
      when others =>
         return Fail
           (Syntax_Error, Line_No, "unexpected LOAM Locus admission reader failure");
   end Read_Content;

   function Read_File (Path : String) return Read_Result is
      Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
        HRA_N.Storage.Exact_File.Read_All (Path);
      Msg   : constant String := "cannot read LOAM Locus admission file";
   begin
      if not Exact.Success then
         return Make_Failure (IO_Error, 0, Msg);
      end if;
      return Read_Content (US.To_String (Exact.Content));
   exception
      when others =>
         return Make_Failure (IO_Error, 0, Msg);
   end Read_File;

   function Format_Error (Result : Read_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Document_Empty        => return "LOAM Locus admission document is empty";
            when Missing_Final_Newline => return "LOAM Locus admission document must end with newline";
            when Unsupported_Header    => return "unsupported LOAM Locus admission header";
            when Syntax_Error          => return "syntax error in LOAM Locus admission document";
            when Invalid_Token         => return "invalid LOAM Locus token";
            when Capacity_Exceeded     => return "HRA-N Locus admission capacity exceeded";
            when Duplicate_Token       => return "duplicate LOAM Locus admission token";
            when IO_Error              => return "cannot read LOAM Locus admission file";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Locus_Admission_Reader;
