-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Routing_Reader
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Exact_File;

package body HRA_N.Storage.Loam_Actual_Routing_Reader is

   use type Ada.Directories.File_Kind;

   package US renames Ada.Strings.Unbounded;

   Header : constant String :=
     "LOAM-ACTUAL-ROUTING" & ASCII.HT & "1";

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

   type Field_Slice is record
      First : Positive;
      Last  : Natural;
   end record;

   type Field_Array is array (Positive range 1 .. 8) of Field_Slice;

   procedure Split_Tabs
     (Line   : String;
      Fields : out Field_Array;
      Count  : out Natural)
   is
      Start : Positive := Line'First;
   begin
      Count := 0;
      if Line'Length = 0 then
         return;
      end if;

      for I in Line'Range loop
         if Line (I) = ASCII.HT then
            if Count < Fields'Last then
               Count := Count + 1;
               Fields (Count) := (First => Start, Last => I - 1);
            end if;
            Start := I + 1;
         end if;
      end loop;

      if Count < Fields'Last then
         Count := Count + 1;
         Fields (Count) := (First => Start, Last => Line'Last);
      end if;
   end Split_Tabs;

   function Make_Failure
     (Status  : Routing_Read_Status;
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

   function Read_Content (Content : String) return Read_Result is
      Result   : Read_Result (Success => True);
      Position : Natural :=
        (if Content'Length = 0 then 0 else Content'First);
      Line_No  : Natural := 0;

      function Fail
        (Status  : Routing_Read_Status;
         At_Line : Natural;
         Message : String) return Read_Result is
      begin
         return Make_Failure (Status, At_Line, Message);
      end Fail;

   begin
      if Content'Length = 0 then
         return Fail (Document_Empty, 0, "LOAM actual routing document is empty");
      elsif Content (Content'Last) /= ASCII.LF then
         return Fail (Missing_Final_Newline, 0, "LOAM actual routing document does not end with LF");
      end if;

      declare
         Line    : US.Unbounded_String;
         Success : Boolean;
      begin
         Next_Line (Content, Position, Line, Success);
         if not Success then
            return Fail (Malformed_Header, 1, "Failed reading header line");
         end if;
         Line_No := 1;

         if US.To_String (Line) /= Header then
            return Fail (Malformed_Header, 1, "Invalid header: expected " & Header);
         end if;

         loop
            Next_Line (Content, Position, Line, Success);
            exit when not Success;
            Line_No := Line_No + 1;

            declare
               Raw : constant String := US.To_String (Line);
            begin
               if Raw'Length = 0 then
                  return Fail (Syntax_Error, Line_No, "Empty line encountered");
               end if;

               declare
                  Fields      : Field_Array;
                  Field_Count : Natural;
               begin
                  Split_Tabs (Raw, Fields, Field_Count);

                  if Field_Count < 4 then
                     return Fail (Syntax_Error, Line_No, "Too few fields in ROUTE row");
                  end if;

                  declare
                     Tag : constant String :=
                       Raw (Fields (1).First .. Fields (1).Last);
                  begin
                     if Tag /= "ROUTE" then
                        return Fail (Syntax_Error, Line_No, "Unknown row tag: " & Tag);
                     end if;
                  end;

                  declare
                     Locus_Str : constant String :=
                       Raw (Fields (2).First .. Fields (2).Last);
                     Mode_Str  : constant String :=
                       Raw (Fields (3).First .. Fields (3).Last);
                     Entry_Rec : Routing_Entry;
                  begin
                     if not Valid_Token (Locus_Str) then
                        return Fail (Invalid_Token, Line_No, "Invalid locus token: " & Locus_Str);
                     end if;
                     Entry_Rec.Locus := (Token => Make_Token (Locus_Str));

                     if Mode_Str = "INITIAL" then
                        Entry_Rec.Effective_Kind := Routing_Initial;
                        declare
                           Managed_Str : constant String :=
                             Raw (Fields (4).First .. Fields (4).Last);
                        begin
                           if Managed_Str = "MANAGED" then
                              if Field_Count < 5 then
                                 return Fail (Syntax_Error, Line_No, "MANAGED route missing purpose");
                              end if;
                              Entry_Rec.Managed := True;
                              declare
                                 Purp_Str : constant String :=
                                   Raw (Fields (5).First .. Fields (5).Last);
                              begin
                                 if not Valid_Token (Purp_Str) then
                                    return Fail (Invalid_Token, Line_No, "Invalid purpose token: " & Purp_Str);
                                 end if;
                                 Entry_Rec.Purpose := Make_Token (Purp_Str);
                              end;
                           elsif Managed_Str = "UNMANAGED" then
                              Entry_Rec.Managed := False;
                           else
                              return Fail (Syntax_Error, Line_No, "Expected MANAGED or UNMANAGED, got: " & Managed_Str);
                           end if;
                        end;

                     elsif Mode_Str = "FROM" then
                        if Field_Count < 5 then
                           return Fail (Syntax_Error, Line_No, "FROM route missing date or managed state");
                        end if;
                        Entry_Rec.Effective_Kind := Routing_From_Date;
                        declare
                           Date_Str : constant String :=
                             Raw (Fields (4).First .. Fields (4).Last);
                           Managed_Str : constant String :=
                             Raw (Fields (5).First .. Fields (5).Last);
                           Parsed_Date : Date_Type;
                        begin
                           if not Parse_Iso_Date (Date_Str, Parsed_Date) then
                              return Fail (Syntax_Error, Line_No, "Invalid date in FROM route: " & Date_Str);
                           end if;
                           Entry_Rec.Effective_On := Parsed_Date;

                           if Managed_Str = "MANAGED" then
                              if Field_Count < 6 then
                                 return Fail (Syntax_Error, Line_No, "MANAGED FROM route missing purpose");
                              end if;
                              Entry_Rec.Managed := True;
                              declare
                                 Purp_Str : constant String :=
                                   Raw (Fields (6).First .. Fields (6).Last);
                              begin
                                 if not Valid_Token (Purp_Str) then
                                    return Fail (Invalid_Token, Line_No, "Invalid purpose token: " & Purp_Str);
                                 end if;
                                 Entry_Rec.Purpose := Make_Token (Purp_Str);
                              end;
                           elsif Managed_Str = "UNMANAGED" then
                              Entry_Rec.Managed := False;
                           else
                              return Fail (Syntax_Error, Line_No, "Expected MANAGED or UNMANAGED, got: " & Managed_Str);
                           end if;
                        end;

                     else
                        return Fail (Syntax_Error, Line_No, "Unknown route mode: " & Mode_Str);
                     end if;

                     if Result.Routing.Count = Max_Routing_Entries then
                        return Fail (Capacity_Exceeded, Line_No, "Exceeded maximum routing entries");
                     end if;

                     Result.Routing.Count := Result.Routing.Count + 1;
                     Result.Routing.Entries (Result.Routing.Count) := Entry_Rec;
                  end;
               end;
            end;
         end loop;
      end;

      if not Coordinates_Are_Unique (Result.Routing) then
         return Fail (Duplicate_Coordinate, Line_No, "Duplicate routing coordinate in actual-routing.loam");
      end if;

      return Result;
   exception
      when others =>
         return Fail (Syntax_Error, Line_No, "unexpected LOAM actual routing reader failure");
   end Read_Content;

   function Read_File (Path : String) return Read_Result is
      Msg : constant String := "required LOAM actual routing file is missing or unreadable";
   begin
      if not Ada.Directories.Exists (Path) then
         return Make_Failure (IO_Error, 0, Msg);
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
            when Document_Empty        => return "LOAM actual routing document is empty";
            when Missing_Final_Newline => return "LOAM actual routing document does not end with LF";
            when Malformed_Header      => return "malformed LOAM actual routing header";
            when Syntax_Error          => return "syntax error in LOAM actual routing document";
            when Invalid_Token         => return "invalid token in LOAM actual routing document";
            when Capacity_Exceeded     => return "exceeded maximum routing entries";
            when Duplicate_Coordinate  => return "duplicate routing coordinate";
            when IO_Error              => return "required LOAM actual routing file is missing or unreadable";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Actual_Routing_Reader;
