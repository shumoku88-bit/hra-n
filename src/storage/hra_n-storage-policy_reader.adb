-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Policy_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with HRA_N.Storage.HRA_Tokenizer;   use HRA_N.Storage.HRA_Tokenizer;

package body HRA_N.Storage.Policy_Reader is

   function Clean_Token (S : String) return String is
      Last : Natural := S'Last;
   begin
      while Last >= S'First and then (S (Last) = ',' or else S (Last) = ':') loop
         Last := Last - 1;
      end loop;
      if Last < S'First then
         return "";
      else
         return S (S'First .. Last);
      end if;
   end Clean_Token;

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

   function Read_Policy_File (Path : String) return Policy_Result is
      File       : Ada.Text_IO.File_Type;
      Result     : Policy_Result;
      Line_Num   : Natural := 0;
      Coord_List : Coordinate_List;

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
            Set_Error ("Cannot open policy file: " & Path);
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
                  if Tag = "ROLE" then
                     if Count < 3 then
                        Set_Error ("Malformed ROLE declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Tok3_Date    : Date_Type;
                        Is_Versioned : constant Boolean :=
                          (Count >= 5 and then Parse_Iso_Date (Slice (Line, Tokens (3)), Tok3_Date));
                     begin
                        if Is_Versioned then
                           declare
                              Id_Str    : constant String := Clean_Token (Slice (Line, Tokens (2)));
                              Locus_Str : constant String := Clean_Token (Slice (Line, Tokens (4)));
                              Role_Str  : constant String := Clean_Token (Slice (Line, Tokens (5)));
                              Role_Val  : Accounting_Role;
                              Has_Rep   : Boolean := False;
                              Rep_Str   : String (1 .. 96) := [others => ' '];
                              Rep_Len   : Natural := 0;
                           begin
                              if Role_Str = "ASSET" then
                                 Role_Val := Role_Asset;
                              elsif Role_Str = "LIABILITY" then
                                 Role_Val := Role_Liability;
                              elsif Role_Str = "INCOME" then
                                 Role_Val := Role_Income;
                              elsif Role_Str = "EXPENSE" then
                                 Role_Val := Role_Expense;
                              elsif Role_Str = "EQUITY" then
                                 Role_Val := Role_Equity;
                              else
                                 Set_Error ("Unknown accounting role: " & Role_Str);
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;

                              if Count >= 7 and then Slice (Line, Tokens (6)) = "REPLACES" then
                                 declare
                                    Target_Str : constant String := Clean_Token (Slice (Line, Tokens (7)));
                                 begin
                                    if Target_Str'Length > 0 then
                                       Has_Rep := True;
                                       Rep_Len := Natural'Min (Target_Str'Length, Rep_Str'Length);
                                       Rep_Str (1 .. Rep_Len) := Target_Str (Target_Str'First .. Target_Str'First + Rep_Len - 1);
                                    end if;
                                 end;
                              end if;

                              if Result.Roles.Count = Max_Role_Assignments then
                                 Set_Error ("Exceeded maximum role assignments");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;

                              Result.Roles.Count := Result.Roles.Count + 1;
                              Result.Roles.Entries (Result.Roles.Count) :=
                                (Id             => Make_Token (Id_Str),
                                 Locus          => (Token => Make_Token (Locus_Str)),
                                 Role           => Role_Val,
                                 Effective_From => Tok3_Date,
                                 Has_Replaces   => Has_Rep,
                                 Replaces       => Make_Token (Rep_Str (1 .. Rep_Len)));
                           end;
                        else
                           declare
                              Role_Str : constant String := Clean_Token (Slice (Line, Tokens (Count)));
                              Role_Val : Accounting_Role;
                           begin
                              if Role_Str = "ASSET" then
                                 Role_Val := Role_Asset;
                              elsif Role_Str = "LIABILITY" then
                                 Role_Val := Role_Liability;
                              elsif Role_Str = "INCOME" then
                                 Role_Val := Role_Income;
                              elsif Role_Str = "EXPENSE" then
                                 Role_Val := Role_Expense;
                              elsif Role_Str = "EQUITY" then
                                 Role_Val := Role_Equity;
                              else
                                 Set_Error ("Unknown accounting role: " & Role_Str);
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;

                              for T in 2 .. Count - 1 loop
                                 declare
                                    Locus_Str : constant String := Clean_Token (Slice (Line, Tokens (T)));
                                 begin
                                    if Locus_Str'Length > 0 then
                                       if Result.Roles.Count = Max_Role_Assignments then
                                          Set_Error ("Exceeded maximum role assignments");
                                          Ada.Text_IO.Close (File);
                                          return Result;
                                       end if;

                                       Result.Roles.Count := Result.Roles.Count + 1;
                                       declare
                                          Syn_Id : constant String := "leg-r" & Natural'Image (Result.Roles.Count);
                                          Trim_Id : constant String :=
                                            (if Syn_Id (6) = ' ' then Syn_Id (1 .. 5) & Syn_Id (7 .. Syn_Id'Last) else Syn_Id);
                                       begin
                                          Result.Roles.Entries (Result.Roles.Count) :=
                                            (Id             => Make_Token (Trim_Id),
                                             Locus          => (Token => Make_Token (Locus_Str)),
                                             Role           => Role_Val,
                                             Effective_From => (Year => 1900, Month => 1, Day => 1),
                                             Has_Replaces   => False,
                                             Replaces       => (Length => 0, Value => [others => ' ']));
                                       end;
                                    end if;
                                 end;
                              end loop;
                           end;
                        end if;
                     end;

                  elsif Tag = "ZERO-ORIGIN" then
                     for T in 2 .. Count loop
                        declare
                           Token_Str : constant String := Clean_Token (Slice (Line, Tokens (T)));
                           Colon_Pos : Natural := 0;
                        begin
                           if Token_Str'Length > 0 then
                              for I in Token_Str'Range loop
                                 if Token_Str (I) = ':' then
                                    Colon_Pos := I;
                                    exit;
                                 end if;
                              end loop;

                              if Coord_List.Count = Max_Coverage_Coordinates then
                                 Set_Error ("Exceeded maximum coverage coordinates");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;

                              Coord_List.Count := Coord_List.Count + 1;
                              if Colon_Pos > 0 then
                                 Coord_List.Values (Coord_List.Count) :=
                                   (Locus   => (Token => Make_Token (Token_Str (Token_Str'First .. Colon_Pos - 1))),
                                    Measure => (Token => Make_Token (Token_Str (Colon_Pos + 1 .. Token_Str'Last))));
                              else
                                 Coord_List.Values (Coord_List.Count) :=
                                   (Locus   => (Token => Make_Token (Token_Str)),
                                    Measure => (Token => Make_Token ("jpy")));
                              end if;
                           end if;
                        end;
                     end loop;

                  elsif Tag = "CAPACITY" then
                     if Count < 3 then
                        Set_Error ("Malformed CAPACITY declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Last_Tok : constant String := Clean_Token (Slice (Line, Tokens (Count)));
                        Amt_Val  : Long_Long_Integer;
                        Curr_Tok : String (1 .. 3) := "jpy";
                     begin
                        if not Parse_Integer (Last_Tok, Amt_Val) then
                           if not Parse_Integer (Clean_Token (Slice (Line, Tokens (Count - 1))), Amt_Val) then
                              Set_Error ("Invalid capacity amount");
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;
                           if Last_Tok'Length <= 3 then
                              Curr_Tok (1 .. Last_Tok'Length) := Last_Tok;
                           end if;
                        end if;

                        declare
                           Purp_Str : constant String := Clean_Token (Slice (Line, Tokens (2)));
                           Mov_Id   : constant String := "cap-" & Natural'Image (Result.Capacities.Movement_Count + 1);
                           Mov      : Capacity_Movement;
                        begin
                           if Result.Capacities.Movement_Count = Max_Capacity_Movements then
                              Set_Error ("Exceeded maximum capacity movements");
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;

                           Mov.Id           := Make_Token (Mov_Id);
                           Mov.Currency     := Make_Token (Curr_Tok);
                           Mov.Change_Count := 2;
                           Mov.Changes (1)  :=
                             (Coord  => Make_Unallocated_Coordinate,
                              Amount => Quanta_Type (-Amt_Val));
                           Mov.Changes (2)  :=
                             (Coord  => Make_Purpose_Coordinate (Make_Token (Purp_Str)),
                              Amount => Quanta_Type (Amt_Val));

                           Result.Capacities.Movement_Count := Result.Capacities.Movement_Count + 1;
                           Result.Capacities.Movements (Result.Capacities.Movement_Count) := Mov;
                        end;
                     end;

                  elsif Tag = "ROUTE" then
                     if Count < 3 then
                        Set_Error ("Malformed ROUTE declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Purp_Str : constant String := Clean_Token (Slice (Line, Tokens (Count)));
                     begin
                        for T in 2 .. Count - 1 loop
                           declare
                              Locus_Str : constant String := Clean_Token (Slice (Line, Tokens (T)));
                           begin
                              if Locus_Str'Length > 0 then
                                 if Result.Routing.Count = Max_Routing_Entries then
                                    Set_Error ("Exceeded maximum routing entries");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;

                                 Result.Routing.Count := Result.Routing.Count + 1;
                                 Result.Routing.Entries (Result.Routing.Count) :=
                                   (Locus   => (Token => Make_Token (Locus_Str)),
                                    Purpose => Make_Token (Purp_Str));
                              end if;
                           end;
                        end loop;
                     end;

                  elsif Tag = "WINDOW" then
                     if Count >= 4 then
                        declare
                           Name_Str  : constant String := Clean_Token (Slice (Line, Tokens (2)));
                           Start_Str : constant String := Slice (Line, Tokens (3));
                           End_Idx   : constant Positive :=
                             (if Count >= 5 and then Slice (Line, Tokens (4)) = "->" then 5 else 4);
                           End_Str   : constant String := Slice (Line, Tokens (End_Idx));
                           Name_Tok_Idx : constant Natural :=
                             (if End_Idx + 1 <= Count
                                and then Tokens (End_Idx + 1).Kind = Tok_Quoted
                              then End_Idx + 1 else 0);
                           Display_Name : constant String :=
                             (if Name_Tok_Idx > 0
                              then Slice (Line, Tokens (Name_Tok_Idx))
                              else Name_Str);
                           S_Date    : Date_Type;
                           E_Date    : Date_Type;
                        begin
                           if Parse_Iso_Date (Start_Str, S_Date) and then Parse_Iso_Date (End_Str, E_Date) then
                              if not Date_Less (S_Date, E_Date) then
                                 Set_Error ("Window start date must be strictly before end date");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;

                              for W in 1 .. Result.Windows.Count loop
                                 if Equal_Token (Result.Windows.Windows (W).Id, Make_Token (Name_Str)) then
                                    Set_Error ("Duplicate window identity: " & Name_Str);
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                              end loop;

                              if Result.Windows.Count = Max_Windows then
                                 Set_Error ("Exceeded maximum windows");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;

                              Result.Windows.Count := Result.Windows.Count + 1;
                              Result.Windows.Windows (Result.Windows.Count) :=
                                (Id         => Make_Token (Name_Str),
                                 Start_Date => S_Date,
                                 End_Date   => E_Date,
                                 Name       => Make_Token (Display_Name));

                              if not Result.Has_Window then
                                 Result.Has_Window   := True;
                                 Result.Window_Name  := Make_Token (Name_Str);
                                 Result.Window_Start := S_Date;
                                 Result.Window_End   := E_Date;
                              end if;
                           else
                              Set_Error ("Invalid date format in WINDOW declaration");
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;
                        end;
                     else
                        Set_Error ("Malformed WINDOW declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);

      if Result.Has_Window then
         Result.Capacities.Effective_Count := Result.Capacities.Movement_Count;
         for I in 1 .. Result.Capacities.Movement_Count loop
            Result.Capacities.Effective (I) :=
              (Movement_Id => Result.Capacities.Movements (I).Id,
               Year        => Result.Window_Start.Year,
               Month       => Result.Window_Start.Month,
               Day         => Result.Window_Start.Day);
         end loop;
      end if;

      if Coordinates_Are_Unique (Coord_List) then
         Result.Coverage := Make_Coverage (Coord_List);
      else
         Set_Error ("Duplicate coordinate in ZERO-ORIGIN coverage");
         return Result;
      end if;

      if not All_Role_Laws_Hold (Result.Roles) then
         Set_Error ("Role declarations violate sound policy laws (duplicate id, conflict, branch, or cycle)");
         return Result;
      end if;

      if not Windows_Are_Sound (Result.Windows) then
         Set_Error ("Window declarations violate sound window laws");
         return Result;
      end if;

      Result.Success := True;
      return Result;

   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Set_Error ("Unexpected I/O exception reading policy");
         return Result;
   end Read_Policy_File;

end HRA_N.Storage.Policy_Reader;
