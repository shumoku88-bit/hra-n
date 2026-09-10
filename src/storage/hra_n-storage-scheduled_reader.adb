-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Scheduled_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;

with HRA_N.Core.Types;        use HRA_N.Core.Types;
with HRA_N.Core.Validity;     use HRA_N.Core.Validity;
with HRA_N.Storage.Validity_Reader; use HRA_N.Storage.Validity_Reader;

package body HRA_N.Storage.Scheduled_Reader is

   type Section_Kind is
     (Section_None,
      Section_Scheduled,
      Section_Completion,
      Section_Retirement,
      Section_Replacement);

   function Set_Error
     (Result : in out Read_Scheduled_Result;
      Line   : Natural;
      Msg    : String) return Read_Scheduled_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Line   := Line;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Read_Scheduled_File (Path : String) return Read_Scheduled_Result is
      File    : Ada.Text_IO.File_Type;
      Result  : Read_Scheduled_Result;
      Line_No : Natural := 0;

      Section : Section_Kind := Section_None;

      Cur_Occ_Active : Boolean := False;
   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Could not open file: " & Path);
      end;

      --  Line 1: Header verification
      if not Ada.Text_IO.End_Of_File (File) then
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            Line_No := Line_No + 1;
            if Line /= "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" then
               Ada.Text_IO.Close (File);
               return Set_Error (Result, Line_No, "Invalid lifecycle header");
            end if;
         end;
      else
         Ada.Text_IO.Close (File);
         return Set_Error (Result, 0, "Empty scheduled lifecycle file");
      end if;

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Raw_Line : constant String := Ada.Text_IO.Get_Line (File);
            Line     : constant String := Trim (Raw_Line, Ada.Strings.Both);
         begin
            Line_No := Line_No + 1;

            if Line'Length > 0 then
               declare
                  Tab_Pos : constant Natural := Index (Line, "" & ASCII.HT);
                  Tag     : constant String  :=
                    (if Tab_Pos > 0 then Line (Line'First .. Tab_Pos - 1) else Line);
                  Rest    : constant String  :=
                    (if Tab_Pos > 0 then Line (Tab_Pos + 1 .. Line'Last) else "");
               begin
                  if Tag = "BEGIN" then
                     if Rest = "Scheduled" then
                        Section := Section_Scheduled;
                     elsif Rest = "Completion" then
                        Section := Section_Completion;
                     elsif Rest = "Retirement" then
                        Section := Section_Retirement;
                     elsif Rest = "Replacement" then
                        Section := Section_Replacement;
                     end if;

                  elsif Tag = "END" then
                     Section := Section_None;
                     Cur_Occ_Active := False;

                  elsif Tag = "LOAM-SCHEDULED-MEMORY"
                    or else Tag = "LOAM-SCHEDULED-COMPLETION-MEMORY"
                    or else Tag = "LOAM-SCHEDULED-RETIREMENT-MEMORY"
                    or else Tag = "LOAM-SCHEDULED-REPLACEMENT-MEMORY"
                  then
                     null;

                  else
                     case Section is
                        when Section_Scheduled =>
                           if Tag = "SCHEDULED" then
                              --  Rest: <id>\t<date>\t<measure>
                              declare
                                 T1 : constant Natural := Index (Rest, "" & ASCII.HT);
                              begin
                                 if T1 = 0 then
                                    Ada.Text_IO.Close (File);
                                    return Set_Error (Result, Line_No, "Malformed SCHEDULED record");
                                 end if;

                                 declare
                                    Id_Str : constant String := Rest (Rest'First .. T1 - 1);
                                    After1 : constant String := Rest (T1 + 1 .. Rest'Last);
                                    T2     : constant Natural := Index (After1, "" & ASCII.HT);
                                 begin
                                    if T2 = 0 then
                                       Ada.Text_IO.Close (File);
                                       return Set_Error (Result, Line_No, "Malformed SCHEDULED date/measure");
                                    end if;

                                    declare
                                       Date_Str : constant String := After1 (After1'First .. T2 - 1);
                                       Meas_Str : constant String := After1 (T2 + 1 .. After1'Last);
                                       Parsed_D : Date_Type;
                                    begin
                                       if not Parse_Iso_Date (Date_Str, Parsed_D) then
                                          Ada.Text_IO.Close (File);
                                          return Set_Error (Result, Line_No, "Invalid ISO date in SCHEDULED");
                                       end if;

                                       if Result.Lifecycle.Sched_Count = Max_Scheduled_Entries then
                                          Ada.Text_IO.Close (File);
                                          return Set_Error (Result, Line_No, "Exceeded maximum scheduled entries");
                                       end if;

                                       Result.Lifecycle.Sched_Count := Result.Lifecycle.Sched_Count + 1;
                                       Result.Lifecycle.Sched_Items (Result.Lifecycle.Sched_Count) :=
                                         (Id           => (Token => Make_Token (Id_Str)),
                                          Expected_Day => Parsed_D,
                                          Measure      => (Token => Make_Token (Meas_Str)),
                                          Changes      => (Count => 0, Values => [others => <>]));
                                       Cur_Occ_Active := True;
                                    end;
                                 end;
                              end;

                           elsif Tag = "CHANGE" then
                              --  Rest: <locus>\t<amount>
                              if not Cur_Occ_Active then
                                 Ada.Text_IO.Close (File);
                                 return Set_Error (Result, Line_No, "CHANGE outside of SCHEDULED block");
                              end if;

                              declare
                                 T1 : constant Natural := Index (Rest, "" & ASCII.HT);
                              begin
                                 if T1 = 0 then
                                    Ada.Text_IO.Close (File);
                                    return Set_Error (Result, Line_No, "Malformed CHANGE record");
                                 end if;

                                 declare
                                    Locus_Str : constant String := Rest (Rest'First .. T1 - 1);
                                    Amt_Str   : constant String := Rest (T1 + 1 .. Rest'Last);
                                    Cur_Idx   : constant Positive := Result.Lifecycle.Sched_Count;
                                    Chg_Count : constant Natural :=
                                      Result.Lifecycle.Sched_Items (Cur_Idx).Changes.Count;
                                    Val       : Quanta_Type;
                                 begin
                                    begin
                                       Val := Quanta_Type'Value (Amt_Str);
                                    exception
                                       when others =>
                                          Ada.Text_IO.Close (File);
                                          return Set_Error (Result, Line_No, "Invalid integer in CHANGE amount");
                                    end;

                                    if Chg_Count >= Max_Changes_Per_Sched then
                                       Ada.Text_IO.Close (File);
                                       return Set_Error (Result, Line_No, "Too many CHANGE records in SCHEDULED");
                                    end if;

                                    Result.Lifecycle.Sched_Items (Cur_Idx).Changes.Count := Chg_Count + 1;
                                    Result.Lifecycle.Sched_Items (Cur_Idx).Changes.Values (Chg_Count + 1) :=
                                      (Locus  => (Token => Make_Token (Locus_Str)),
                                       Amount => Val);
                                 end;
                              end;
                           else
                              Ada.Text_IO.Close (File);
                              return Set_Error (Result, Line_No, "Unrecognized record in Scheduled section");
                           end if;

                        when Section_Completion =>
                           if Tag = "COMPLETION" then
                              --  Rest: <scheduled-id>\t<event-id>
                              declare
                                 T1 : constant Natural := Index (Rest, "" & ASCII.HT);
                              begin
                                 if T1 = 0 then
                                    Ada.Text_IO.Close (File);
                                    return Set_Error (Result, Line_No, "Malformed COMPLETION record");
                                 end if;

                                 declare
                                    Sched_Str : constant String := Rest (Rest'First .. T1 - 1);
                                    Ev_Str    : constant String := Rest (T1 + 1 .. Rest'Last);
                                 begin
                                    if Result.Lifecycle.Comp_Count = Max_Scheduled_Entries then
                                       Ada.Text_IO.Close (File);
                                       return Set_Error (Result, Line_No, "Too many COMPLETION records");
                                    end if;

                                    Result.Lifecycle.Comp_Count := Result.Lifecycle.Comp_Count + 1;
                                    Result.Lifecycle.Comp_Items (Result.Lifecycle.Comp_Count) :=
                                      (Scheduled => (Token => Make_Token (Sched_Str)),
                                       Actual    => (Token => Make_Token (Ev_Str)));
                                 end;
                              end;
                           else
                              Ada.Text_IO.Close (File);
                              return Set_Error (Result, Line_No, "Unrecognized record in Completion section");
                           end if;

                        when Section_Retirement =>
                           if Tag = "RETIREMENT" then
                              if Result.Lifecycle.Ret_Count = Max_Scheduled_Entries then
                                 Ada.Text_IO.Close (File);
                                 return Set_Error (Result, Line_No, "Too many RETIREMENT records");
                              end if;

                              Result.Lifecycle.Ret_Count := Result.Lifecycle.Ret_Count + 1;
                              Result.Lifecycle.Ret_Items (Result.Lifecycle.Ret_Count) :=
                                (Scheduled => (Token => Make_Token (Rest)));
                           else
                              Ada.Text_IO.Close (File);
                              return Set_Error (Result, Line_No, "Unrecognized record in Retirement section");
                           end if;

                        when Section_Replacement =>
                           if Tag = "REPLACEMENT" then
                              declare
                                 T1 : constant Natural := Index (Rest, "" & ASCII.HT);
                              begin
                                 if T1 = 0 then
                                    Ada.Text_IO.Close (File);
                                    return Set_Error (Result, Line_No, "Malformed REPLACEMENT record");
                                 end if;

                                 declare
                                    Orig_Str : constant String := Rest (Rest'First .. T1 - 1);
                                    Repl_Str : constant String := Rest (T1 + 1 .. Rest'Last);
                                 begin
                                    if Result.Lifecycle.Repl_Count = Max_Scheduled_Entries then
                                       Ada.Text_IO.Close (File);
                                       return Set_Error (Result, Line_No, "Too many REPLACEMENT records");
                                    end if;

                                    Result.Lifecycle.Repl_Count := Result.Lifecycle.Repl_Count + 1;
                                    Result.Lifecycle.Repl_Items (Result.Lifecycle.Repl_Count) :=
                                      (Original    => (Token => Make_Token (Orig_Str)),
                                       Replaced_By => (Token => Make_Token (Repl_Str)));
                                 end;
                              end;
                           else
                              Ada.Text_IO.Close (File);
                              return Set_Error (Result, Line_No, "Unrecognized record in Replacement section");
                           end if;

                        when Section_None =>
                           Ada.Text_IO.Close (File);
                           return Set_Error (Result, Line_No, "Record outside of any section");
                     end case;
                  end if;
               end;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);
      Result.Success := True;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Set_Error (Result, Line_No, "Unexpected exception during Scheduled parsing");
   end Read_Scheduled_File;

end HRA_N.Storage.Scheduled_Reader;
