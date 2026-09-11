-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Policy_Reader
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;
with Ada.Text_IO;
with HRA_N.Core.Description; use HRA_N.Core.Description;
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

   function Format_Cap_Id (Number : Positive) return String is
      Image_Text : constant String :=
        Ada.Strings.Fixed.Trim (Number'Image, Ada.Strings.Both);
   begin
      return "cap" & (1 .. Natural'Max (0, 4 - Image_Text'Length) => '0') & Image_Text;
   end Format_Cap_Id;

   --  Parse one capacity endpoint: the `unallocated` boundary or a purpose.
   --  A purpose is never silently a physical locus; the wrapper carries that.
   procedure Parse_Cap_Coord
     (Text   : String;
      Coord  : out Capacity_Coordinate;
      Valid  : out Boolean)
   is
   begin
      Coord := HRA_N.Core.Capacity.Empty_Coordinate;
      Valid := False;
      if Text = "unallocated" then
         Coord := Make_Unallocated_Coordinate;
         Valid := True;
      elsif Text'Length > 0 and then Text'Length <= Max_Token_Length then
         Coord := Make_Purpose_Coordinate (Make_Token (Text));
         Valid := True;
      end if;
   end Parse_Cap_Coord;

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
                        Curr_Str : String (1 .. Max_Token_Length) := [others => ' '];
                        Curr_Len : Natural := 3;
                     begin
                        Curr_Str (1 .. 3) := "jpy";
                        if not Parse_Integer (Last_Tok, Amt_Val) then
                           if not Parse_Integer (Clean_Token (Slice (Line, Tokens (Count - 1))), Amt_Val)
                             or else Last_Tok'Length = 0
                             or else Last_Tok'Length > Max_Token_Length
                           then
                              Set_Error ("Invalid capacity amount or currency");
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;
                           Curr_Len := Last_Tok'Length;
                           Curr_Str (1 .. Curr_Len) := Last_Tok;
                        end if;

                        declare
                           Purp_Str : constant String := Clean_Token (Slice (Line, Tokens (2)));
                           Mov_Id   : constant String :=
                             Format_Cap_Id (Result.Capacities.Movement_Count + 1);
                           Mov      : Capacity_Movement;
                        begin
                           if Result.Capacities.Movement_Count = Max_Capacity_Movements then
                              Set_Error ("Exceeded maximum capacity movements");
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;

                           if Purp_Str'Length = 0
                             or else Purp_Str'Length > Max_Token_Length
                           then
                              Set_Error ("Invalid capacity purpose");
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;

                           if Amt_Val > Long_Long_Integer (Quanta_Type'Last)
                             or else Amt_Val < Long_Long_Integer (Quanta_Type'First)
                           then
                              Set_Error ("Capacity amount out of range");
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;

                           Mov.Id           := Make_Token (Mov_Id);
                           Mov.Currency     := Make_Token (Curr_Str (1 .. Curr_Len));
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

                  elsif Tag = "TRANSFER" then
                     --  Explicit two-endpoint capacity movement with its own
                     --  effective date: TRANSFER <from> <to> <amount>
                     --  <currency> <YYYY-MM-DD>. No operation kind is stored;
                     --  grant, transfer, and return are endpoint readings.
                     if Count /= 6 then
                        Set_Error ("Malformed TRANSFER declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        From_Str : constant String := Clean_Token (Slice (Line, Tokens (2)));
                        To_Str   : constant String := Clean_Token (Slice (Line, Tokens (3)));
                        Amt_Str  : constant String := Slice (Line, Tokens (4));
                        Curr_Str : constant String := Clean_Token (Slice (Line, Tokens (5)));
                        Date_Str : constant String := Slice (Line, Tokens (6));
                        From_C, To_C : Capacity_Coordinate;
                        From_Ok, To_Ok : Boolean;
                        Amt_Val  : Long_Long_Integer;
                        Eff_Date : Date_Type;
                        Mov      : Capacity_Movement;
                     begin
                        Parse_Cap_Coord (From_Str, From_C, From_Ok);
                        Parse_Cap_Coord (To_Str, To_C, To_Ok);
                        if not From_Ok or else not To_Ok then
                           Set_Error ("Invalid TRANSFER endpoint");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Equal_Coordinate (From_C, To_C) then
                           Set_Error ("TRANSFER endpoints must be distinct");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif not Parse_Integer (Amt_Str, Amt_Val)
                          or else Amt_Val <= 0
                          or else Amt_Val > Long_Long_Integer (Quanta_Type'Last)
                        then
                           Set_Error ("Invalid TRANSFER amount");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Curr_Str'Length = 0
                          or else Curr_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid TRANSFER currency");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif not Parse_Iso_Date (Date_Str, Eff_Date) then
                           Set_Error ("Invalid TRANSFER effective date");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Result.Capacities.Movement_Count = Max_Capacity_Movements
                          or else Result.Capacities.Effective_Count = Max_Capacity_Movements
                        then
                           Set_Error ("Exceeded maximum capacity movements");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;

                        Mov.Id           := Make_Token
                          (Format_Cap_Id (Result.Capacities.Movement_Count + 1));
                        Mov.Currency     := Make_Token (Curr_Str);
                        Mov.Change_Count := 2;
                        Mov.Changes (1)  :=
                          (Coord  => From_C, Amount => Quanta_Type (-Amt_Val));
                        Mov.Changes (2)  :=
                          (Coord  => To_C, Amount => Quanta_Type (Amt_Val));
                        Result.Capacities.Movement_Count :=
                          Result.Capacities.Movement_Count + 1;
                        Result.Capacities.Movements (Result.Capacities.Movement_Count) := Mov;
                        Result.Capacities.Effective_Count :=
                          Result.Capacities.Effective_Count + 1;
                        Result.Capacities.Effective (Result.Capacities.Effective_Count) :=
                          (Movement_Id => Mov.Id,
                           Year        => Eff_Date.Year,
                           Month       => Eff_Date.Month,
                           Day         => Eff_Date.Day);
                     end;

                  elsif Tag = "REBALANCE" then
                     --  Multi-endpoint capacity movement: REBALANCE <currency>
                     --  <YYYY-MM-DD> <coord:amount> [<coord:amount> ...].
                     --  Signed changes must be nonzero, duplicate-free, and
                     --  sum exactly to zero.
                     if Count < 5 then
                        Set_Error ("Malformed REBALANCE declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Curr_Str : constant String := Clean_Token (Slice (Line, Tokens (2)));
                        Date_Str : constant String := Slice (Line, Tokens (3));
                        Eff_Date : Date_Type;
                        Mov      : Capacity_Movement;
                        Total    : Long_Long_Integer := 0;
                     begin
                        if Curr_Str'Length = 0
                          or else Curr_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid REBALANCE currency");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif not Parse_Iso_Date (Date_Str, Eff_Date) then
                           Set_Error ("Invalid REBALANCE effective date");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Count - 3 > Max_Changes_Per_Movement then
                           Set_Error ("Too many REBALANCE changes");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Result.Capacities.Movement_Count = Max_Capacity_Movements
                          or else Result.Capacities.Effective_Count = Max_Capacity_Movements
                        then
                           Set_Error ("Exceeded maximum capacity movements");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;

                        Mov.Id       := Make_Token
                          (Format_Cap_Id (Result.Capacities.Movement_Count + 1));
                        Mov.Currency := Make_Token (Curr_Str);
                        Mov.Change_Count := 0;
                        for T in 4 .. Count loop
                           declare
                              Pair_Str  : constant String := Slice (Line, Tokens (T));
                              Colon_Pos : Natural := 0;
                              Amt_Val   : Long_Long_Integer;
                              Coord     : Capacity_Coordinate;
                              Coord_Ok  : Boolean;
                           begin
                              for I in reverse Pair_Str'Range loop
                                 if Pair_Str (I) = ':' then
                                    Colon_Pos := I;
                                    exit;
                                 end if;
                              end loop;
                              if Colon_Pos = Pair_Str'First
                                or else Colon_Pos = 0
                                or else Colon_Pos = Pair_Str'Last
                                or else not Parse_Integer
                                  (Pair_Str (Colon_Pos + 1 .. Pair_Str'Last), Amt_Val)
                              then
                                 Set_Error ("Malformed REBALANCE change: " & Pair_Str);
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;
                              Parse_Cap_Coord
                                (Pair_Str (Pair_Str'First .. Colon_Pos - 1), Coord, Coord_Ok);
                              if not Coord_Ok
                                or else Amt_Val = 0
                                or else Amt_Val > Long_Long_Integer (Quanta_Type'Last)
                                or else Amt_Val < Long_Long_Integer (Quanta_Type'First)
                              then
                                 Set_Error ("Invalid REBALANCE change: " & Pair_Str);
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;
                              for Seen in 1 .. Mov.Change_Count loop
                                 if Equal_Coordinate (Mov.Changes (Seen).Coord, Coord) then
                                    Set_Error ("Duplicate REBALANCE coordinate: " & Pair_Str);
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                              end loop;
                              Mov.Change_Count := Mov.Change_Count + 1;
                              Mov.Changes (Mov.Change_Count) :=
                                (Coord => Coord, Amount => Quanta_Type (Amt_Val));
                              Total := Total + Amt_Val;
                           end;
                        end loop;
                        if Total /= 0 then
                           Set_Error ("REBALANCE changes must balance to zero");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        Result.Capacities.Movement_Count :=
                          Result.Capacities.Movement_Count + 1;
                        Result.Capacities.Movements (Result.Capacities.Movement_Count) := Mov;
                        Result.Capacities.Effective_Count :=
                          Result.Capacities.Effective_Count + 1;
                        Result.Capacities.Effective (Result.Capacities.Effective_Count) :=
                          (Movement_Id => Mov.Id,
                           Year        => Eff_Date.Year,
                           Month       => Eff_Date.Month,
                           Day         => Eff_Date.Day);
                     end;

                  elsif Tag = "EFFECTIVE" then
                     --  Standalone effective-date evidence for movements that
                     --  carry none inline (legacy CAPACITY lines). At most one
                     --  coordinate per movement; inline-dated movements must
                     --  not gain a second one.
                     if Count /= 3 then
                        Set_Error ("Malformed EFFECTIVE declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Id_Str   : constant String := Clean_Token (Slice (Line, Tokens (2)));
                        Date_Str : constant String := Slice (Line, Tokens (3));
                        Eff_Date : Date_Type;
                     begin
                        if Id_Str'Length = 0
                          or else Id_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid EFFECTIVE identity");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif not Parse_Iso_Date (Date_Str, Eff_Date) then
                           Set_Error ("Invalid EFFECTIVE date");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Result.Capacities.Effective_Count = Max_Capacity_Movements then
                           Set_Error ("Exceeded maximum capacity effective entries");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        Result.Capacities.Effective_Count :=
                          Result.Capacities.Effective_Count + 1;
                        Result.Capacities.Effective (Result.Capacities.Effective_Count) :=
                          (Movement_Id => Make_Token (Id_Str),
                           Year        => Eff_Date.Year,
                           Month       => Eff_Date.Month,
                           Day         => Eff_Date.Day);
                     end;

                  elsif Tag = "ATTENTION" then
                     --  Retained household matter: ATTENTION <id> "<context>"
                     --  <due:YYYY-MM-DD | nodue | due-unknown>. Due meaning
                     --  is explicit; a missing due word is never guessed.
                     if Count /= 4
                       or else Tokens (3).Kind /= Tok_Quoted
                     then
                        Set_Error ("Malformed ATTENTION declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Id_Str   : constant String := Clean_Token (Slice (Line, Tokens (2)));
                        Ctx_Str  : constant String := Slice (Line, Tokens (3));
                        Due_Str  : constant String := Slice (Line, Tokens (4));
                        Due      : Attention_Due;
                        Due_Date : Date_Type;
                     begin
                        if Id_Str'Length = 0
                          or else Id_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid ATTENTION identity");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Ctx_Str'Length = 0
                          or else Ctx_Str'Length > Max_Description_Length
                        then
                           Set_Error ("Invalid ATTENTION context");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Due_Str = "nodue" then
                           Due := (Kind => No_Due_Date);
                        elsif Due_Str = "due-unknown" then
                           Due := (Kind => Due_Undetermined);
                        elsif Due_Str'Length > 4
                          and then Due_Str (Due_Str'First .. Due_Str'First + 3) = "due:"
                          and then Parse_Iso_Date
                            (Due_Str (Due_Str'First + 4 .. Due_Str'Last), Due_Date)
                        then
                           Due := (Kind => Due_On_Date, Due_Date => Due_Date);
                        else
                           Set_Error ("Invalid ATTENTION due meaning");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        if Result.Attention.Item_Count = Max_Attention_Items then
                           Set_Error ("Exceeded maximum attention items");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        Result.Attention.Item_Count := Result.Attention.Item_Count + 1;
                        Result.Attention.Items (Result.Attention.Item_Count) :=
                          (Id      => Make_Token (Id_Str),
                           Context => Make_Description (Ctx_Str),
                           Due     => Due);
                     end;

                  elsif Tag = "ATTENTION-CLOSE" then
                     --  Explicit lifecycle evidence: ATTENTION-CLOSE <id>
                     --  <resolved | dropped> <YYYY-MM-DD>. At most one per
                     --  item; provenance never closes.
                     if Count /= 4 then
                        Set_Error ("Malformed ATTENTION-CLOSE declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Id_Str   : constant String := Clean_Token (Slice (Line, Tokens (2)));
                        Kind_Str : constant String := Slice (Line, Tokens (3));
                        Date_Str : constant String := Slice (Line, Tokens (4));
                        Kind     : Closure_Kind;
                        Known    : Date_Type;
                     begin
                        if Id_Str'Length = 0
                          or else Id_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid ATTENTION-CLOSE identity");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Kind_Str = "resolved" then
                           Kind := Closure_Resolved;
                        elsif Kind_Str = "dropped" then
                           Kind := Closure_Dropped;
                        else
                           Set_Error ("Invalid ATTENTION-CLOSE kind");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        if not Parse_Iso_Date (Date_Str, Known) then
                           Set_Error ("Invalid ATTENTION-CLOSE date");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Result.Attention.Close_Count = Max_Attention_Items then
                           Set_Error ("Exceeded maximum attention closures");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        Result.Attention.Close_Count := Result.Attention.Close_Count + 1;
                        Result.Attention.Closures (Result.Attention.Close_Count) :=
                          (Target   => Make_Token (Id_Str),
                           Kind     => Kind,
                           Known_On => Known);
                     end;

                  elsif Tag = "ROUTE" then
                     --  Historical form:
                     --    ROUTE <locus> INITIAL MANAGED <purpose>
                     --    ROUTE <locus> INITIAL UNMANAGED
                     --    ROUTE <locus> FROM <date> MANAGED <purpose>
                     --    ROUTE <locus> FROM <date> UNMANAGED
                     --  Legacy grouped ROUTE loci... purpose rows remain
                     --  initial managed assertions for compatibility.
                     if Count < 3 then
                        Set_Error ("Malformed ROUTE declaration");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Form : constant String := Slice (Line, Tokens (3));
                     begin
                        if Form = "INITIAL" or else Form = "FROM" then
                           declare
                              Is_Initial : constant Boolean := Form = "INITIAL";
                              State_Idx  : constant Positive :=
                                (if Is_Initial then 4 else 5);
                              Purpose_Idx : constant Positive := State_Idx + 1;
                              Locus_Str : constant String :=
                                Clean_Token (Slice (Line, Tokens (2)));
                              State_Str : constant String :=
                                (if Count >= State_Idx
                                 then Slice (Line, Tokens (State_Idx)) else "");
                              Date_Val : Date_Type :=
                                (Year => 1900, Month => 1, Day => 1);
                              Managed : constant Boolean := State_Str = "MANAGED";
                              Purpose : Token_Text :=
                                (Length => 0, Value => [others => ' ']);
                           begin
                              if (Is_Initial
                                  and then Count not in 4 .. 5)
                                or else ((not Is_Initial)
                                         and then Count not in 5 .. 6)
                                or else (State_Str /= "MANAGED"
                                         and then State_Str /= "UNMANAGED")
                                or else (Managed and then Count /= Purpose_Idx)
                                or else ((not Managed) and then Count /= State_Idx)
                              then
                                 Set_Error ("Malformed historical ROUTE declaration");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              elsif Locus_Str'Length = 0
                                or else Locus_Str'Length > Max_Token_Length
                              then
                                 Set_Error ("Invalid ROUTE locus");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              elsif not Is_Initial
                                and then not Parse_Iso_Date
                                  (Slice (Line, Tokens (4)), Date_Val)
                              then
                                 Set_Error ("Invalid ROUTE effective date");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;

                              if Managed then
                                 declare
                                    Purp_Str : constant String :=
                                      Clean_Token
                                        (Slice (Line, Tokens (Purpose_Idx)));
                                 begin
                                    if Purp_Str'Length = 0
                                      or else Purp_Str'Length > Max_Token_Length
                                    then
                                       Set_Error ("Invalid ROUTE purpose");
                                       Ada.Text_IO.Close (File);
                                       return Result;
                                    end if;
                                    Purpose := Make_Token (Purp_Str);
                                 end;
                              end if;

                              if Result.Routing.Count = Max_Routing_Entries then
                                 Set_Error ("Exceeded maximum routing entries");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;
                              Result.Routing.Count := Result.Routing.Count + 1;
                              Result.Routing.Entries (Result.Routing.Count) :=
                                (Locus          => (Token => Make_Token (Locus_Str)),
                                 Effective_Kind =>
                                   (if Is_Initial then Routing_Initial
                                    else Routing_From_Date),
                                 Effective_On   => Date_Val,
                                 Managed        => Managed,
                                 Purpose        => Purpose);
                           end;
                        else
                           declare
                              Purp_Str : constant String :=
                                Clean_Token (Slice (Line, Tokens (Count)));
                           begin
                              if Purp_Str'Length = 0
                                or else Purp_Str'Length > Max_Token_Length
                              then
                                 Set_Error ("Invalid legacy ROUTE purpose");
                                 Ada.Text_IO.Close (File);
                                 return Result;
                              end if;
                              for T in 2 .. Count - 1 loop
                                 declare
                                    Locus_Str : constant String :=
                                      Clean_Token (Slice (Line, Tokens (T)));
                                 begin
                                    if Locus_Str'Length > 0 then
                                       if Locus_Str'Length > Max_Token_Length
                                         or else Result.Routing.Count =
                                           Max_Routing_Entries
                                       then
                                          Set_Error ("Invalid or excessive ROUTE locus");
                                          Ada.Text_IO.Close (File);
                                          return Result;
                                       end if;
                                       Result.Routing.Count :=
                                         Result.Routing.Count + 1;
                                       Result.Routing.Entries
                                         (Result.Routing.Count) :=
                                         (Locus          =>
                                            (Token => Make_Token (Locus_Str)),
                                          Effective_Kind => Routing_Initial,
                                          Effective_On   =>
                                            (Year => 1900, Month => 1, Day => 1),
                                          Managed        => True,
                                          Purpose        => Make_Token (Purp_Str));
                                    end if;
                                 end;
                              end loop;
                           end;
                        end if;
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

      if not All_Movements_Conserved (Result.Capacities) then
         Set_Error ("Capacity movement breaks conservation");
         return Result;
      elsif not Effective_References_Are_Closed (Result.Capacities) then
         Set_Error ("Capacity effective references unknown movement");
         return Result;
      elsif not Effectives_Are_One_To_One (Result.Capacities) then
         Set_Error ("Duplicate capacity effective coordinate");
         return Result;
      elsif not Item_Ids_Are_Unique (Result.Attention) then
         Set_Error ("Duplicate attention identity");
         return Result;
      elsif not Closure_References_Are_Closed (Result.Attention) then
         Set_Error ("Attention closure references unknown item");
         return Result;
      elsif not Closures_Are_One_To_One (Result.Attention) then
         Set_Error ("Duplicate attention closure");
         return Result;
      elsif not Coordinates_Are_Unique (Result.Routing) then
         Set_Error ("Duplicate Actual routing effective coordinate");
         return Result;
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
