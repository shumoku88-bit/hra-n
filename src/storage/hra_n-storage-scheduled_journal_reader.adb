-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Journal_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with HRA_N.Core.Types;              use HRA_N.Core.Types;
with HRA_N.Core.Validity;           use HRA_N.Core.Validity;
with HRA_N.Storage.HRA_Tokenizer;   use HRA_N.Storage.HRA_Tokenizer;

package body HRA_N.Storage.Scheduled_Journal_Reader is

   function Parse_Integer (S : String; Val : out Long_Long_Integer) return Boolean is
      Sign  : Long_Long_Integer := 1;
      First : Positive := S'First;
      Res   : Long_Long_Integer := 0;
   begin
      if S'Length = 0 then
         return False;
      end if;

      if S (First) = '-' then
         Sign := -1;
         First := First + 1;
      elsif S (First) = '+' then
         First := First + 1;
      end if;

      if First > S'Last then
         return False;
      end if;

      for I in First .. S'Last loop
         if S (I) not in '0' .. '9' then
            return False;
         end if;
         Res := Res * 10 + Long_Long_Integer (Character'Pos (S (I)) - Character'Pos ('0'));
      end loop;

      Val := Res * Sign;
      return True;
   end Parse_Integer;

   procedure Parse_Flow
     (Tok     : String;
      Locus   : out Token_Text;
      Measure : out Token_Text;
      Amount  : out Quanta_Type;
      Success : out Boolean)
   is
      Last_Colon : Natural := 0;
      Prev_Colon : Natural := 0;
      Amt_Val    : Long_Long_Integer;
   begin
      Success := False;
      Locus   := Make_Token ("");
      Measure := Make_Token ("jpy");
      Amount  := Zero_Quanta;

      for I in Tok'Range loop
         if Tok (I) = ':' then
            Prev_Colon := Last_Colon;
            Last_Colon := I;
         end if;
      end loop;

      if Last_Colon = 0 then
         return;
      end if;

      if Parse_Integer (Tok (Last_Colon + 1 .. Tok'Last), Amt_Val) then
         Amount  := Quanta_Type (Amt_Val);
         Measure := Make_Token ("jpy");
         Locus   := Make_Token (Tok (Tok'First .. Last_Colon - 1));
         Success := True;
      elsif Prev_Colon > 0
        and then Parse_Integer (Tok (Prev_Colon + 1 .. Last_Colon - 1), Amt_Val)
      then
         Amount  := Quanta_Type (Amt_Val);
         Measure := Make_Token (Tok (Last_Colon + 1 .. Tok'Last));
         Locus   := Make_Token (Tok (Tok'First .. Prev_Colon - 1));
         Success := True;
      end if;
   end Parse_Flow;

   function Read_Scheduled_Journal_File (Path : String) return Scheduled_Journal_Result is
      File     : Ada.Text_IO.File_Type;
      Result   : Scheduled_Journal_Result;
      Line_Num : Natural := 0;

      procedure Set_Error (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Line := Line_Num;
         Result.Error_Len := L;
         Result.Error_Reason (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Set_Error;

   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      exception
         when others =>
            Set_Error ("Cannot open scheduled file: " & Path);
            return Result;
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line   : constant String := Ada.Text_IO.Get_Line (File);
            Tokens : Token_Array;
            Count  : Natural;
         begin
            Tokenize_Line (Line, Tokens, Count);

            if Count > 0 then
               declare
                  Tag : constant String := Slice (Line, Tokens (1));
               begin
                  if Tag = "COMPLETE" then
                     if Count /= 3
                       or else Result.Lifecycle.Comp_Count = Max_Scheduled_Entries
                     then
                        Set_Error ("Malformed or excessive COMPLETE fact");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;
                     Result.Lifecycle.Comp_Count := Result.Lifecycle.Comp_Count + 1;
                     Result.Lifecycle.Comp_Items (Result.Lifecycle.Comp_Count) :=
                       (Scheduled => (Token => Make_Token (Slice (Line, Tokens (2)))),
                        Actual    => (Token => Make_Token (Slice (Line, Tokens (3)))));
                  elsif Tag = "RETIRE" then
                     if Count /= 2
                       or else Result.Lifecycle.Ret_Count = Max_Scheduled_Entries
                     then
                        Set_Error ("Malformed or excessive RETIRE fact");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;
                     Result.Lifecycle.Ret_Count := Result.Lifecycle.Ret_Count + 1;
                     Result.Lifecycle.Ret_Items (Result.Lifecycle.Ret_Count) :=
                       (Scheduled => (Token => Make_Token (Slice (Line, Tokens (2)))));
                  elsif Tag = "REPLACE" then
                     if Count /= 3
                       or else Result.Lifecycle.Repl_Count = Max_Scheduled_Entries
                     then
                        Set_Error ("Malformed or excessive REPLACE fact");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;
                     Result.Lifecycle.Repl_Count := Result.Lifecycle.Repl_Count + 1;
                     Result.Lifecycle.Repl_Items (Result.Lifecycle.Repl_Count) :=
                       (Original    => (Token => Make_Token (Slice (Line, Tokens (2)))),
                        Replaced_By => (Token => Make_Token (Slice (Line, Tokens (3)))));
                  elsif Tag /= "SCHED" then
                     Set_Error ("Unknown scheduled fact header: " & Tag);
                     Ada.Text_IO.Close (File);
                     return Result;
                  else
                  if Count < 4 then
                     Set_Error ("Malformed SCHED record: insufficient tokens");
                     Ada.Text_IO.Close (File);
                     return Result;
                  end if;

                  declare
                     Id_Str      : constant String := Slice (Line, Tokens (2));
                     Date_Str    : constant String := Slice (Line, Tokens (3));
                     Parsed_Date : Date_Type;
                     Occ         : Scheduled_Occurrence;
                  begin
                     if not Parse_Iso_Date (Date_Str, Parsed_Date) then
                        Set_Error ("Invalid ISO date in SCHED record: " & Date_Str);
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     Occ.Id.Token     := Make_Token (Id_Str);
                     Occ.Expected_Day := Parsed_Date;
                     Occ.Measure      := (Token => Make_Token ("jpy"));
                     Occ.Changes.Count := 0;

                     for T in 4 .. Count loop
                        declare
                           Tok_Str : constant String := Slice (Line, Tokens (T));
                        begin
                           if Tok_Str'Length >= 7 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 6) = "status:" then
                              declare
                                 Stat_Val : constant String := Tok_Str (Tok_Str'First + 7 .. Tok_Str'Last);
                              begin
                                 if Stat_Val = "open" then
                                    null;
                                 elsif Stat_Val = "retired" then
                                    if Result.Lifecycle.Ret_Count = Max_Scheduled_Entries then
                                       Set_Error ("Exceeded maximum retirement entries");
                                       Ada.Text_IO.Close (File);
                                       return Result;
                                    end if;
                                    Result.Lifecycle.Ret_Count := Result.Lifecycle.Ret_Count + 1;
                                    Result.Lifecycle.Ret_Items (Result.Lifecycle.Ret_Count) :=
                                      (Scheduled => (Token => Make_Token (Id_Str)));
                                 elsif Stat_Val'Length > 10 and then Stat_Val (Stat_Val'First .. Stat_Val'First + 9) = "completed:" then
                                    declare
                                       Ref_Id : constant String := Stat_Val (Stat_Val'First + 10 .. Stat_Val'Last);
                                    begin
                                       if Result.Lifecycle.Comp_Count = Max_Scheduled_Entries then
                                          Set_Error ("Exceeded maximum completion entries");
                                          Ada.Text_IO.Close (File);
                                          return Result;
                                       end if;
                                       Result.Lifecycle.Comp_Count := Result.Lifecycle.Comp_Count + 1;
                                       Result.Lifecycle.Comp_Items (Result.Lifecycle.Comp_Count) :=
                                         (Scheduled => (Token => Make_Token (Id_Str)),
                                          Actual    => (Token => Make_Token (Ref_Id)));
                                    end;
                                 elsif Stat_Val'Length > 12 and then Stat_Val (Stat_Val'First .. Stat_Val'First + 11) = "replaced-by:" then
                                    declare
                                       New_Id : constant String := Stat_Val (Stat_Val'First + 12 .. Stat_Val'Last);
                                    begin
                                       if Result.Lifecycle.Repl_Count = Max_Scheduled_Entries then
                                          Set_Error ("Exceeded maximum replacement entries");
                                          Ada.Text_IO.Close (File);
                                          return Result;
                                       end if;
                                       Result.Lifecycle.Repl_Count := Result.Lifecycle.Repl_Count + 1;
                                       Result.Lifecycle.Repl_Items (Result.Lifecycle.Repl_Count) :=
                                         (Original    => (Token => Make_Token (Id_Str)),
                                          Replaced_By => (Token => Make_Token (New_Id)));
                                    end;
                                 else
                                    Set_Error ("Unknown scheduled status: " & Stat_Val);
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                              end;
                           else
                              --  Flow token
                              declare
                                 Locus   : Token_Text;
                                 Measure : Token_Text;
                                 Amt     : Quanta_Type;
                                 Flow_Ok : Boolean;
                              begin
                                 Parse_Flow (Tok_Str, Locus, Measure, Amt, Flow_Ok);
                                 if not Flow_Ok then
                                    Set_Error ("Malformed flow in SCHED record: " & Tok_Str);
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;

                                 if Occ.Changes.Count = Max_Changes_Per_Sched then
                                    Set_Error ("Exceeded maximum changes per scheduled item");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;

                                 Occ.Changes.Count := Occ.Changes.Count + 1;
                                 Occ.Changes.Values (Occ.Changes.Count) :=
                                   (Locus  => (Token => Locus),
                                    Amount => Amt);
                                 Occ.Measure := (Token => Measure);
                              end;
                           end if;
                        end;
                     end loop;

                     if Result.Lifecycle.Sched_Count = Max_Scheduled_Entries then
                        Set_Error ("Exceeded maximum scheduled entries");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     Result.Lifecycle.Sched_Count := Result.Lifecycle.Sched_Count + 1;
                     Result.Lifecycle.Sched_Items (Result.Lifecycle.Sched_Count) := Occ;
                  end;
                  end if;
               end;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);
      if not Scheduled_Ids_Are_Unique (Result.Lifecycle)
        or else not Completions_Reference_Known (Result.Lifecycle)
        or else not Retirements_Reference_Known (Result.Lifecycle)
        or else not Replacements_Reference_Known (Result.Lifecycle)
        or else not Terminal_Targets_Are_Unique (Result.Lifecycle)
        or else not Replacements_Are_One_To_One (Result.Lifecycle)
        or else not Replacement_History_Is_Acyclic (Result.Lifecycle)
      then
         Set_Error ("Scheduled lifecycle facts violate admission laws");
         return Result;
      end if;
      Result.Success := True;
      return Result;

   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Set_Error ("Unexpected I/O exception reading scheduled journal");
         return Result;
   end Read_Scheduled_Journal_File;

end HRA_N.Storage.Scheduled_Journal_Reader;
