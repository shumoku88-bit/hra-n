-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Exact_File;

package body HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader is

   use type Ada.Directories.File_Kind;

   package US renames Ada.Strings.Unbounded;

   Header : constant String :=
     "LOAM-ZERO-ORIGIN-COVERAGE" & ASCII.HT & "1";

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

   function Empty_Result (Present : Boolean) return Read_Result is
      Result : Read_Result (Success => True);
      Empty  : Coordinate_List;
   begin
      Result.Present := Present;
      Result.Coverage := Make_Coverage (Empty);
      return Result;
   end Empty_Result;

   function Make_Failure
     (Status   : Coverage_Read_Status;
      At_Line  : Natural;
      Message  : String) return Read_Result
   is
      Result : Read_Result (Success => False);
      Len    : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.Present := True;
      Result.Status := Status;
      Result.Error_Line := At_Line;
      Result.Error_Len := Len;
      if Len > 0 then
         Result.Error_Reason (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end if;
      return Result;
   end Make_Failure;

   function Read_Content (Content : String) return Read_Result is
      Coords   : Coordinate_List;
      Position : Natural := (if Content'Length = 0 then 0 else Content'First);
      Line_No  : Natural := 0;

      function Fail
        (Status  : Coverage_Read_Status;
         At_Line : Natural;
         Message : String) return Read_Result
      is
      begin
         return Make_Failure (Status, At_Line, Message);
      end Fail;
   begin
      if Content'Length = 0 then
         return Fail (Document_Empty, 0, "LOAM zero-origin coverage document is empty");
      elsif Content (Content'Last) /= ASCII.LF then
         return Fail (Missing_Final_Newline, 0, "LOAM zero-origin coverage document must end with newline");
      end if;

      declare
         First     : US.Unbounded_String;
         Have_Line : Boolean;
      begin
         Next_Line (Content, Position, First, Have_Line);
         if not Have_Line or else US.To_String (First) /= Header then
            return Fail (Unsupported_Header, 1, "unsupported LOAM zero-origin coverage header");
         end if;
         Line_No := 1;
      end;

      while Position <= Content'Last loop
         declare
            Raw       : US.Unbounded_String;
            Have_Line : Boolean;
         begin
            Next_Line (Content, Position, Raw, Have_Line);
            Line_No := Line_No + 1;
            if not Have_Line then
               return Fail (Syntax_Error, Line_No, "unterminated COORDINATE row");
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
                 or else Line (Line'First .. First_Tab - 1) /= "COORDINATE"
                 or else Second_Tab = Line'Last
               then
                  return Fail (Syntax_Error, Line_No, "expected COORDINATE locus measure row");
               end if;

               declare
                  Locus_Text : constant String := Line (First_Tab + 1 .. Second_Tab - 1);
                  Measure_Text : constant String := Line (Second_Tab + 1 .. Line'Last);
                  Candidate : Coordinate_Type;
               begin
                  if not Valid_Token (Locus_Text)
                    or else not Valid_Token (Measure_Text)
                  then
                     return Fail (Invalid_Token, Line_No, "invalid LOAM zero-origin coordinate token");
                  elsif Coords.Count = Max_Coverage_Coordinates then
                     return Fail (Capacity_Exceeded, Line_No, "HRA-N zero-origin coverage capacity exceeded");
                  end if;

                  Candidate :=
                    (Locus   => (Token => Make_Token (Locus_Text)),
                     Measure => (Token => Make_Token (Measure_Text)));
                  for I in 1 .. Coords.Count loop
                     if Equal_Coordinate (Coords.Values (I), Candidate) then
                        return Fail (Duplicate_Coordinate, Line_No, "duplicate LOAM zero-origin coordinate");
                     end if;
                  end loop;
                  Coords.Count := Coords.Count + 1;
                  Coords.Values (Coords.Count) := Candidate;
               end;
            end;
         end;
      end loop;

      if not Coordinates_Are_Unique (Coords) then
         return Fail (Duplicate_Coordinate, Line_No, "duplicate LOAM zero-origin coordinate");
      end if;

      declare
         Result : Read_Result (Success => True);
      begin
         Result.Present := True;
         Result.Coverage := Make_Coverage (Coords);
         return Result;
      end;
   exception
      when others =>
         return Fail (Syntax_Error, Line_No, "unexpected LOAM zero-origin coverage reader failure");
   end Read_Content;

   function Read_File (Path : String) return Read_Result is
      Msg : constant String := "cannot read LOAM zero-origin coverage file";
   begin
      if not Ada.Directories.Exists (Path) then
         return Empty_Result (Present => False);
      end if;

      if Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         return Make_Failure (IO_Error, 0, Msg);
      end if;

      declare
         Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Path);
      begin
         if not Exact.Success then
            return Make_Failure (IO_Error, 0, Msg);
         end if;
         return Read_Content (US.To_String (Exact.Content));
      end;
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
            when Document_Empty        => return "LOAM zero-origin coverage document is empty";
            when Missing_Final_Newline => return "LOAM zero-origin coverage document must end with newline";
            when Unsupported_Header    => return "unsupported LOAM zero-origin coverage header";
            when Syntax_Error          => return "syntax error in LOAM zero-origin coverage document";
            when Invalid_Token         => return "invalid LOAM zero-origin coordinate token";
            when Capacity_Exceeded     => return "HRA-N zero-origin coverage capacity exceeded";
            when Duplicate_Coordinate  => return "duplicate LOAM zero-origin coordinate";
            when IO_Error              => return "cannot read LOAM zero-origin coverage file";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader;
