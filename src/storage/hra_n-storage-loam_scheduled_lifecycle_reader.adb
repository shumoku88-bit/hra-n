-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Exact_File;

package body HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader is

   package US renames Ada.Strings.Unbounded;

   Lifecycle_Header : constant String :=
     "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1";
   Scheduled_Header : constant String :=
     "LOAM-SCHEDULED-MEMORY" & ASCII.HT & "1";
   Completion_Header : constant String :=
     "LOAM-SCHEDULED-COMPLETION-MEMORY" & ASCII.HT & "1";
   Retirement_Header : constant String :=
     "LOAM-SCHEDULED-RETIREMENT-MEMORY" & ASCII.HT & "1";
   Replacement_Header : constant String :=
     "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & ASCII.HT & "1";

   type Field_Array is array (Positive range 1 .. 4) of US.Unbounded_String;

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

   procedure Split_Tab
     (Line     : String;
      Fields   : out Field_Array;
      Count    : out Natural;
      Overflow : out Boolean)
   is
      Start : Natural := Line'First;
      procedure Push (First, Last : Natural) is
      begin
         if Count = Fields'Length then
            Overflow := True;
            return;
         end if;
         Count := Count + 1;
         if Last < First then
            Fields (Count) := US.Null_Unbounded_String;
         else
            Fields (Count) :=
              US.To_Unbounded_String (Line (First .. Last));
         end if;
      end Push;
   begin
      Fields := [others => US.Null_Unbounded_String];
      Count := 0;
      Overflow := False;

      if Line'Length = 0 then
         Push (1, 0);
         return;
      end if;

      for I in Line'Range loop
         if Line (I) = ASCII.HT then
            Push (Start, I - 1);
            if Overflow then
               return;
            end if;
            Start := I + 1;
         end if;
      end loop;
      Push (Start, Line'Last);
   end Split_Tab;

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

   function Parse_Quanta
     (Text : String;
      Value : out Quanta_Type) return Boolean
   is
      Raw : Long_Long_Integer;
   begin
      if Text'Length = 0 then
         return False;
      end if;
      begin
         Raw := Long_Long_Integer'Value (Text);
      exception
         when others =>
            return False;
      end;
      if Raw < Long_Long_Integer (Quanta_Type'First)
        or else Raw > Long_Long_Integer (Quanta_Type'Last)
      then
         return False;
      end if;
      Value := Quanta_Type (Raw);
      return True;
   end Parse_Quanta;

   function Completion_Mentions_Actual
     (Result    : Read_Result;
      Actual_Id : Event_Id) return Boolean
   is
   begin
      if not Result.Success then
         return False;
      end if;
      for I in 1 .. Result.Lifecycle.Comp_Count loop
         if Equal_Token
           (Result.Lifecycle.Comp_Items (I).Actual.Token, Actual_Id.Token)
         then
            return True;
         end if;
      end loop;
      return False;
   end Completion_Mentions_Actual;

   function Make_Failure
     (Status  : Lifecycle_Read_Status;
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

      Current      : Scheduled_Occurrence :=
        (Id           => (Token => Make_Token ("")),
         Expected_Day => (Year => 2026, Month => 1, Day => 1),
         Measure      => (Token => Make_Token ("")),
         Changes      =>
           (Count  => 0,
            Values => [others =>
              (Locus  => (Token => Make_Token ("")),
               Amount => 0)]));
      Have_Current : Boolean := False;

      function Fail
        (Status  : Lifecycle_Read_Status;
         At_Line : Natural;
         Message : String) return Read_Result is
      begin
         return Make_Failure (Status, At_Line, Message);
      end Fail;

      procedure Read_Line
        (Line : out US.Unbounded_String;
         Ok   : out Boolean)
      is
      begin
         Next_Line (Content, Position, Line, Ok);
         if Ok then
            Line_No := Line_No + 1;
         end if;
      end Read_Line;

      function Expect (Text : String) return Boolean is
         Raw : US.Unbounded_String;
         Ok  : Boolean;
      begin
         Read_Line (Raw, Ok);
         return Ok and then US.To_String (Raw) = Text;
      end Expect;

      function Scheduled_Id_Already_Seen (Id : Token_Text) return Boolean is
      begin
         for I in 1 .. Result.Lifecycle.Sched_Count loop
            if Equal_Token
              (Result.Lifecycle.Sched_Items (I).Id.Token, Id)
            then
               return True;
            end if;
         end loop;
         return False;
      end Scheduled_Id_Already_Seen;

      procedure Finish_Current (Ok : out Boolean) is
         Total : Long_Long_Integer := 0;
      begin
         Ok := False;
         if not Have_Current then
            Ok := True;
            return;
         end if;

         for I in 1 .. Current.Changes.Count loop
            Total := Total + Long_Long_Integer
              (Current.Changes.Values (I).Amount);
         end loop;

         if Total /= 0
           or else Scheduled_Id_Already_Seen (Current.Id.Token)
           or else Result.Lifecycle.Sched_Count = Max_Scheduled_Entries
         then
            return;
         end if;

         Result.Lifecycle.Sched_Count := Result.Lifecycle.Sched_Count + 1;
         Result.Lifecycle.Sched_Items (Result.Lifecycle.Sched_Count) := Current;
         Have_Current := False;
         Ok := True;
      end Finish_Current;

      function Completion_Unique
        (Scheduled : Token_Text;
         Actual    : Token_Text) return Boolean
      is
      begin
         for I in 1 .. Result.Lifecycle.Comp_Count loop
            if Equal_Token
              (Result.Lifecycle.Comp_Items (I).Scheduled.Token, Scheduled)
              or else Equal_Token
                (Result.Lifecycle.Comp_Items (I).Actual.Token, Actual)
            then
               return False;
            end if;
         end loop;
         return True;
      end Completion_Unique;

      function Retirement_Unique (Scheduled : Token_Text) return Boolean is
      begin
         for I in 1 .. Result.Lifecycle.Ret_Count loop
            if Equal_Token
              (Result.Lifecycle.Ret_Items (I).Scheduled.Token, Scheduled)
            then
               return False;
            end if;
         end loop;
         return True;
      end Retirement_Unique;

      function Replacement_Unique
        (Source, Target : Token_Text) return Boolean
      is
      begin
         for I in 1 .. Result.Lifecycle.Repl_Count loop
            if Equal_Token
              (Result.Lifecycle.Repl_Items (I).Original.Token, Source)
              or else Equal_Token
                (Result.Lifecycle.Repl_Items (I).Replaced_By.Token, Target)
            then
               return False;
            end if;
         end loop;
         return True;
      end Replacement_Unique;

   begin
      if Content'Length = 0 then
         return Fail (Document_Empty, 0, "LOAM Scheduled lifecycle document is empty");
      elsif Content (Content'Last) /= ASCII.LF then
         return Fail (Missing_Final_Newline, 0, "LOAM Scheduled lifecycle must end with newline");
      end if;

      if not Expect (Lifecycle_Header) then
         return Fail (Malformed_Header, Line_No, "unsupported LOAM Scheduled lifecycle header");
      elsif not Expect ("BEGIN" & ASCII.HT & "Scheduled") then
         return Fail (Syntax_Error, Line_No, "expected Scheduled section");
      elsif not Expect (Scheduled_Header) then
         return Fail (Malformed_Header, Line_No, "unsupported LOAM Scheduled memory header");
      end if;

      --  Scheduled section.  Empty movement change lists are valid in Loam;
      --  only exact zero total is required by BalancedMovement.
      loop
         declare
            Raw : US.Unbounded_String;
            Ok  : Boolean;
         begin
            Read_Line (Raw, Ok);
            if not Ok then
               return Fail (Syntax_Error, Line_No + 1, "unterminated Scheduled section");
            end if;

            declare
               Line : constant String := US.To_String (Raw);
               Fields : Field_Array;
               Count : Natural;
               Overflow : Boolean;
            begin
               if Line = "END" & ASCII.HT & "Scheduled" then
                  declare
                     Finished : Boolean;
                  begin
                     Finish_Current (Finished);
                     if not Finished then
                        return Fail
                          (Unconserved_Scheduled, Line_No, "Scheduled occurrence violates supported balance or capacity");
                     end if;
                  end;
                  exit;
               end if;

               Split_Tab (Line, Fields, Count, Overflow);
               if Overflow or else Count = 0 then
                  return Fail (Syntax_Error, Line_No, "malformed Scheduled row");
               end if;

               if US.To_String (Fields (1)) = "SCHEDULED" then
                  if Count /= 4 then
                     return Fail (Syntax_Error, Line_No, "malformed SCHEDULED row");
                  end if;

                  declare
                     Finished : Boolean;
                     Id_Text : constant String := US.To_String (Fields (2));
                     Day_Text : constant String := US.To_String (Fields (3));
                     Measure_Text : constant String := US.To_String (Fields (4));
                     Day : Date_Type;
                  begin
                     Finish_Current (Finished);
                     if not Finished then
                        return Fail
                          (Unconserved_Scheduled, Line_No, "previous Scheduled occurrence violates supported balance or capacity");
                     elsif not Valid_Token (Id_Text)
                       or else not Valid_Token (Measure_Text)
                       or else not Parse_Iso_Date (Day_Text, Day)
                     then
                        return Fail (Invalid_Token, Line_No, "invalid SCHEDULED identity, date, or Measure");
                     end if;

                     Current :=
                       (Id           => (Token => Make_Token (Id_Text)),
                        Expected_Day => Day,
                        Measure      => (Token => Make_Token (Measure_Text)),
                        Changes      =>
                          (Count  => 0,
                           Values => [others =>
                             (Locus  => (Token => Make_Token ("")),
                              Amount => 0)]));
                     Have_Current := True;
                  end;
               elsif US.To_String (Fields (1)) = "CHANGE" then
                  if Count /= 3 or else not Have_Current then
                     return Fail (Syntax_Error, Line_No, "CHANGE row has no Scheduled occurrence");
                  end if;

                  declare
                     Locus_Text : constant String := US.To_String (Fields (2));
                     Amount_Text : constant String := US.To_String (Fields (3));
                     Amount : Quanta_Type;
                  begin
                     if not Valid_Token (Locus_Text) then
                        return Fail (Invalid_Token, Line_No, "invalid Scheduled CHANGE locus token");
                     elsif not Parse_Quanta (Amount_Text, Amount) then
                        return Fail (Syntax_Error, Line_No, "invalid Scheduled CHANGE amount");
                     elsif Current.Changes.Count = Max_Changes_Per_Sched then
                        return Fail (Capacity_Exceeded, Line_No, "exceeded maximum changes per Scheduled occurrence");
                     end if;
                     Current.Changes.Count := Current.Changes.Count + 1;
                     Current.Changes.Values (Current.Changes.Count) :=
                       (Locus  => (Token => Make_Token (Locus_Text)),
                        Amount => Amount);
                  end;
               else
                  return Fail (Syntax_Error, Line_No, "unexpected row in Scheduled section");
               end if;
            end;
         end;
      end loop;

      if not Expect ("BEGIN" & ASCII.HT & "Completion") then
         return Fail (Syntax_Error, Line_No, "expected Completion section");
      elsif not Expect (Completion_Header) then
         return Fail (Malformed_Header, Line_No, "unsupported Completion memory header");
      end if;

      loop
         declare
            Raw : US.Unbounded_String;
            Ok  : Boolean;
         begin
            Read_Line (Raw, Ok);
            if not Ok then
               return Fail (Syntax_Error, Line_No + 1, "unterminated Completion section");
            end if;
            declare
               Line : constant String := US.To_String (Raw);
               Fields : Field_Array;
               Count : Natural;
               Overflow : Boolean;
            begin
               if Line = "END" & ASCII.HT & "Completion" then
                  exit;
               end if;
               Split_Tab (Line, Fields, Count, Overflow);
               if Overflow or else Count /= 3
                 or else US.To_String (Fields (1)) /= "COMPLETION"
               then
                  return Fail (Syntax_Error, Line_No, "malformed COMPLETION row");
               end if;
               declare
                  Scheduled_Text : constant String := US.To_String (Fields (2));
                  Actual_Text    : constant String := US.To_String (Fields (3));
                  Scheduled_Tok  : Token_Text;
                  Actual_Tok     : Token_Text;
               begin
                  if not Valid_Token (Scheduled_Text)
                    or else not Valid_Token (Actual_Text)
                  then
                     return Fail (Invalid_Token, Line_No, "invalid COMPLETION endpoint token");
                  end if;
                  Scheduled_Tok := Make_Token (Scheduled_Text);
                  Actual_Tok := Make_Token (Actual_Text);
                  if Result.Lifecycle.Comp_Count = Max_Scheduled_Entries then
                     return Fail (Capacity_Exceeded, Line_No, "exceeded maximum COMPLETION entries");
                  elsif not Completion_Unique (Scheduled_Tok, Actual_Tok) then
                     return Fail (Duplicate_Target, Line_No, "duplicate COMPLETION evidence");
                  end if;
                  Result.Lifecycle.Comp_Count := Result.Lifecycle.Comp_Count + 1;
                  Result.Lifecycle.Comp_Items (Result.Lifecycle.Comp_Count) :=
                    (Scheduled => (Token => Scheduled_Tok),
                     Actual    => (Token => Actual_Tok));
               end;
            end;
         end;
      end loop;

      if not Expect ("BEGIN" & ASCII.HT & "Retirement") then
         return Fail (Syntax_Error, Line_No, "expected Retirement section");
      elsif not Expect (Retirement_Header) then
         return Fail (Malformed_Header, Line_No, "unsupported Retirement memory header");
      end if;

      loop
         declare
            Raw : US.Unbounded_String;
            Ok  : Boolean;
         begin
            Read_Line (Raw, Ok);
            if not Ok then
               return Fail (Syntax_Error, Line_No + 1, "unterminated Retirement section");
            end if;
            declare
               Line : constant String := US.To_String (Raw);
               Fields : Field_Array;
               Count : Natural;
               Overflow : Boolean;
            begin
               if Line = "END" & ASCII.HT & "Retirement" then
                  exit;
               end if;
               Split_Tab (Line, Fields, Count, Overflow);
               if Overflow or else Count /= 2
                 or else US.To_String (Fields (1)) /= "RETIREMENT"
               then
                  return Fail (Syntax_Error, Line_No, "malformed RETIREMENT row");
               end if;
               declare
                  Scheduled_Text : constant String := US.To_String (Fields (2));
                  Scheduled_Tok  : Token_Text;
               begin
                  if not Valid_Token (Scheduled_Text) then
                     return Fail (Invalid_Token, Line_No, "invalid RETIREMENT token");
                  end if;
                  Scheduled_Tok := Make_Token (Scheduled_Text);
                  if Result.Lifecycle.Ret_Count = Max_Scheduled_Entries then
                     return Fail (Capacity_Exceeded, Line_No, "exceeded maximum RETIREMENT entries");
                  elsif not Retirement_Unique (Scheduled_Tok) then
                     return Fail (Duplicate_Target, Line_No, "duplicate RETIREMENT evidence");
                  end if;
                  Result.Lifecycle.Ret_Count := Result.Lifecycle.Ret_Count + 1;
                  Result.Lifecycle.Ret_Items (Result.Lifecycle.Ret_Count) :=
                    (Scheduled => (Token => Scheduled_Tok));
               end;
            end;
         end;
      end loop;

      if not Expect ("BEGIN" & ASCII.HT & "Replacement") then
         return Fail (Syntax_Error, Line_No, "expected Replacement section");
      elsif not Expect (Replacement_Header) then
         return Fail (Malformed_Header, Line_No, "unsupported Replacement memory header");
      end if;

      loop
         declare
            Raw : US.Unbounded_String;
            Ok  : Boolean;
         begin
            Read_Line (Raw, Ok);
            if not Ok then
               return Fail (Syntax_Error, Line_No + 1, "unterminated Replacement section");
            end if;
            declare
               Line : constant String := US.To_String (Raw);
               Fields : Field_Array;
               Count : Natural;
               Overflow : Boolean;
            begin
               if Line = "END" & ASCII.HT & "Replacement" then
                  exit;
               end if;
               Split_Tab (Line, Fields, Count, Overflow);
               if Overflow or else Count /= 3
                 or else US.To_String (Fields (1)) /= "REPLACEMENT"
               then
                  return Fail (Syntax_Error, Line_No, "malformed REPLACEMENT row");
               end if;
               declare
                  Source_Text : constant String := US.To_String (Fields (2));
                  Target_Text : constant String := US.To_String (Fields (3));
                  Source_Tok  : Token_Text;
                  Target_Tok  : Token_Text;
               begin
                  if not Valid_Token (Source_Text)
                    or else not Valid_Token (Target_Text)
                  then
                     return Fail (Invalid_Token, Line_No, "invalid REPLACEMENT endpoint token");
                  end if;
                  Source_Tok := Make_Token (Source_Text);
                  Target_Tok := Make_Token (Target_Text);
                  if Result.Lifecycle.Repl_Count = Max_Scheduled_Entries then
                     return Fail (Capacity_Exceeded, Line_No, "exceeded maximum REPLACEMENT entries");
                  elsif not Replacement_Unique (Source_Tok, Target_Tok) then
                     return Fail (Duplicate_Target, Line_No, "duplicate REPLACEMENT evidence");
                  end if;
                  Result.Lifecycle.Repl_Count := Result.Lifecycle.Repl_Count + 1;
                  Result.Lifecycle.Repl_Items (Result.Lifecycle.Repl_Count) :=
                    (Original    => (Token => Source_Tok),
                     Replaced_By => (Token => Target_Tok));
               end;
            end;
         end;
      end loop;

      if Position <= Content'Last then
         return Fail
           (Unexpected_Trailing_Bytes, Line_No + 1, "unexpected bytes after Replacement section");
      end if;

      return Result;

   exception
      when others =>
         return Fail
           (Syntax_Error, Line_No, "unexpected LOAM Scheduled lifecycle reader failure");
   end Read_Content;

   function Read_File (Path : String) return Read_Result is
      Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
        HRA_N.Storage.Exact_File.Read_All (Path);
      Msg : constant String := "cannot read LOAM Scheduled lifecycle file";
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
            when Document_Empty             => return "LOAM Scheduled lifecycle document is empty";
            when Missing_Final_Newline      => return "LOAM Scheduled lifecycle document does not end with LF";
            when Malformed_Header           => return "malformed LOAM Scheduled lifecycle header";
            when Syntax_Error               => return "syntax error in LOAM Scheduled lifecycle document";
            when Invalid_Token              => return "invalid token in LOAM Scheduled lifecycle document";
            when Capacity_Exceeded          => return "exceeded maximum Scheduled entries";
            when Unconserved_Scheduled      => return "unconserved Scheduled occurrence";
            when Duplicate_Target           => return "duplicate Scheduled lifecycle target";
            when Unexpected_Trailing_Bytes  => return "unexpected bytes after Replacement section";
            when IO_Error                   => return "cannot read LOAM Scheduled lifecycle file";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
