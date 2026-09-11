-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Journal_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with HRA_N.Core.Types;              use HRA_N.Core.Types;
with HRA_N.Storage.HRA_Tokenizer;   use HRA_N.Storage.HRA_Tokenizer;

package body HRA_N.Storage.Journal_Reader is

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

      --  Check if part after last colon is integer (e.g. locus:100 or locus:sub:-192)
      if Parse_Integer (Tok (Last_Colon + 1 .. Tok'Last), Amt_Val) then
         Amount  := Quanta_Type (Amt_Val);
         Measure := Make_Token ("jpy");
         Locus   := Make_Token (Tok (Tok'First .. Last_Colon - 1));
         Success := True;
      elsif Prev_Colon > 0
        and then Parse_Integer (Tok (Prev_Colon + 1 .. Last_Colon - 1), Amt_Val)
      then
         --  locus:100:usd or locus:sub:100:jpy
         Amount  := Quanta_Type (Amt_Val);
         Measure := Make_Token (Tok (Last_Colon + 1 .. Tok'Last));
         Locus   := Make_Token (Tok (Tok'First .. Prev_Colon - 1));
         Success := True;
      end if;
   end Parse_Flow;

   procedure Parse_Endpoint
     (Tok      : String;
      Endpoint : out Relation_Endpoint;
      Valid    : out Boolean)
   is
   begin
      Endpoint := Empty_Endpoint;
      Valid := False;
      if Tok = "household" then
         Endpoint := Household_Endpoint;
         Valid := True;
      elsif Tok'Length > 4
        and then Tok (Tok'First .. Tok'First + 3) = "ext:"
        and then Tok'Length - 4 in 1 .. Max_Token_Length
      then
         Endpoint :=
           External_Endpoint
             (Make_Token (Tok (Tok'First + 4 .. Tok'Last)));
         Valid := True;
      end if;
   end Parse_Endpoint;

   function Read_Journal_File (Path : String) return Journal_Result is
      File      : Ada.Text_IO.File_Type;
      Result    : Journal_Result;
      Line_Num  : Natural := 0;

      Val_List  : Validity_Entry_List;
      Desc_List : Description_Entry_List;
      Meta_List : Metadata_List;
      Rel_Mem   : Relation_Memory;

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
            Set_Error ("Cannot open journal file: " & Path);
            return Result;
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         Line_Num := Line_Num + 1;
         declare
            Line     : constant String := Ada.Text_IO.Get_Line (File);
            Tokens   : Token_Array;
            Count    : Natural;
         begin
            Tokenize_Line (Line, Tokens, Count);

            if Count > 0 then
               declare
                  Tag : constant String := Slice (Line, Tokens (1));
               begin
                  if Tag = "TX" then
                     if Count < 4 then
                        Set_Error ("Malformed TX record: insufficient tokens");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Ev_Id_Str   : constant String := Slice (Line, Tokens (2));
                        Date_Str    : constant String := Slice (Line, Tokens (3));
                        Parsed_Date : Date_Type;
                        Effects     : Effect_List;
                        Note_Text   : Description_Text := (Length => 0, Value => [others => ' ']);
                        Has_Note    : Boolean := False;
                        Meta        : Transaction_Metadata_Entry := Empty_Entry;
                     begin
                        if not Parse_Iso_Date (Date_Str, Parsed_Date) then
                           Set_Error ("Invalid ISO date in TX record: " & Date_Str);
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;

                        --  Check collision with assertion IDs
                        for I in 1 .. Result.Assertions.Count loop
                           if Equal_Token (Result.Assertions.Values (I).Id.Token, Make_Token (Ev_Id_Str)) then
                              Set_Error ("Event ID collides with ASSERT ID: " & Ev_Id_Str);
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;
                        end loop;

                        Meta.Event := (Token => Make_Token (Ev_Id_Str));

                        --  Parse flows and optional metadata
                        for T in 4 .. Count loop
                           declare
                              Tok_Str : constant String := Slice (Line, Tokens (T));
                           begin
                              if Tokens (T).Kind = Tok_Quoted then
                                 if Has_Note or else Tok_Str'Length > Max_Description_Length then
                                    Set_Error ("Invalid or duplicate description metadata");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                                 Note_Text := Make_Description (Tok_Str);
                                 Has_Note := True;
                              elsif Tok_Str'Length > 0 and then Tok_Str (Tok_Str'First) = '@' then
                                 if Meta.Purpose.Present or else Tok_Str'Length = 1
                                   or else Tok_Str'Length - 1 > Max_Token_Length
                                 then
                                    Set_Error ("Invalid or duplicate purpose metadata");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                                 Meta.Purpose :=
                                   (Present => True,
                                    Value => Make_Token
                                      (Tok_Str (Tok_Str'First + 1 .. Tok_Str'Last)));
                              elsif Tok_Str'Length >= 9 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 8) = "replaces:" then
                                 if Meta.Replaces.Present or else Tok_Str'Length = 9
                                   or else Tok_Str'Length - 9 > Max_Token_Length
                                 then
                                    Set_Error ("Invalid or duplicate replacement metadata");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                                 Meta.Replaces :=
                                   (Present => True,
                                    Value => (Token => Make_Token
                                      (Tok_Str (Tok_Str'First + 9 .. Tok_Str'Last))));
                              elsif Tok_Str'Length >= 9 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 8) = "reverses:" then
                                 if Meta.Reverses.Present or else Tok_Str'Length = 9
                                   or else Tok_Str'Length - 9 > Max_Token_Length
                                 then
                                    Set_Error ("Invalid or duplicate reversal metadata");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                                 Meta.Reverses :=
                                   (Present => True,
                                    Value => (Token => Make_Token
                                      (Tok_Str (Tok_Str'First + 9 .. Tok_Str'Last))));
                              elsif Tok_Str'Length >= 9 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 8) = "relation:" then
                                 if Meta.Relation.Present or else Tok_Str'Length = 9
                                   or else Tok_Str'Length - 9 > Max_Token_Length
                                 then
                                    Set_Error ("Invalid or duplicate relation metadata");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                                 Meta.Relation :=
                                   (Present => True,
                                    Value => Make_Token
                                      (Tok_Str (Tok_Str'First + 9 .. Tok_Str'Last)));
                              elsif (Tok_Str'Length >= 11 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 10) = "discharges:")
                                or else (Tok_Str'Length >= 10 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 9) = "discharge:")
                              then
                                 declare
                                    Pref_Len : constant Positive :=
                                      (if Tok_Str (Tok_Str'First .. Tok_Str'First + 9) = "discharge:" then 10 else 11);
                                 begin
                                    if Meta.Discharge.Present or else Tok_Str'Length = Pref_Len
                                      or else Tok_Str'Length - Pref_Len > Max_Token_Length
                                    then
                                       Set_Error ("Invalid or duplicate discharge metadata");
                                       Ada.Text_IO.Close (File);
                                       return Result;
                                    end if;
                                    Meta.Discharge :=
                                      (Present => True,
                                       Value   => Make_Token
                                         (Tok_Str (Tok_Str'First + Pref_Len .. Tok_Str'Last)));
                                 end;
                              elsif Tok_Str'Length >= 11 and then Tok_Str (Tok_Str'First .. Tok_Str'First + 10) = "settlement:" then
                                 if Meta.Discharge.Present or else Tok_Str'Length = 11
                                   or else Tok_Str'Length - 11 > Max_Token_Length
                                 then
                                    Set_Error ("Invalid or duplicate settlement metadata");
                                    Ada.Text_IO.Close (File);
                                    return Result;
                                 end if;
                                 Meta.Discharge :=
                                   (Present => True,
                                    Value => Make_Token
                                      (Tok_Str (Tok_Str'First + 11 .. Tok_Str'Last)));
                              else
                                 --  Must be a flow
                                 declare
                                    Locus   : Token_Text;
                                    Measure : Token_Text;
                                    Amt     : Quanta_Type;
                                    Flow_Ok : Boolean;
                                    Key_Str : constant String := "f" & Natural'Image (Effects.Count + 1);
                                 begin
                                    Parse_Flow (Tok_Str, Locus, Measure, Amt, Flow_Ok);
                                    if not Flow_Ok then
                                       Set_Error ("Malformed flow token: " & Tok_Str);
                                       Ada.Text_IO.Close (File);
                                       return Result;
                                    end if;

                                    Effects.Count := Effects.Count + 1;
                                    Effects.Values (Effects.Count) :=
                                      (Key     => (Token => Make_Token (Key_Str)),
                                       Locus   => (Token => Locus),
                                       Measure => (Token => Measure),
                                       Amount  => (Quanta => Amt));
                                 end;
                              end if;
                           end;
                        end loop;

                        if Effects.Count = 0 then
                           Set_Error ("TX record has no flows");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;

                        --  Construct and append Event
                        declare
                           Ev : constant Event := Make_Event
                             (Id      => (Token => Make_Token (Ev_Id_Str)),
                              Effects => Effects);
                        begin
                           Result.Events.Append (Ev);
                        end;

                        --  Record identity-keyed facts. Every Event receives one
                        --  metadata row, including an all-absent row.
                        if Val_List.Count = Max_Validity_Entries
                          or else Meta_List.Count = Max_Metadata_Entries
                        then
                           Set_Error ("Journal exceeds admitted event capacity");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        Val_List.Count := Val_List.Count + 1;
                        Val_List.Values (Val_List.Count) :=
                          (Event_Id => (Token => Make_Token (Ev_Id_Str)),
                           Valid_On => Parsed_Date);
                        Meta_List.Count := Meta_List.Count + 1;
                        Meta_List.Values (Meta_List.Count) := Meta;

                        --  Record Description fact
                        if Has_Note and then Desc_List.Count < Max_Description_Entries then
                           Desc_List.Count := Desc_List.Count + 1;
                           Desc_List.Values (Desc_List.Count) :=
                             (Event_Id => (Token => Make_Token (Ev_Id_Str)),
                              Text     => Note_Text);
                        end if;
                     end;
                  elsif Tag = "ASSERT" then
                     if Count < 5 then
                        Set_Error ("Malformed ASSERT record: insufficient tokens");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        As_Id_Str   : constant String := Slice (Line, Tokens (2));
                        Date_Str    : constant String := Slice (Line, Tokens (3));
                        Coord_Str   : constant String := Slice (Line, Tokens (4));
                        Amt_Str     : constant String := Slice (Line, Tokens (5));
                        Parsed_Date : Date_Type;
                        Amt_Val     : Long_Long_Integer;
                        Loc_Tok     : Token_Text;
                        Mea_Tok     : Token_Text := Make_Token ("jpy");
                        Colon_Pos   : Natural := 0;
                        Desc_Tok    : Token_Text := Make_Token ("");
                        Add_Ok      : Boolean := False;
                     begin
                        if not Parse_Iso_Date (Date_Str, Parsed_Date) then
                           Set_Error ("Invalid ISO date in ASSERT record: " & Date_Str);
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;

                        if not Parse_Integer (Amt_Str, Amt_Val) then
                           Set_Error ("Invalid amount in ASSERT record: " & Amt_Str);
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;

                        for I in Coord_Str'Range loop
                           if Coord_Str (I) = ':' then
                              Colon_Pos := I;
                              exit;
                           end if;
                        end loop;

                        if Colon_Pos > 0 then
                           Loc_Tok := Make_Token (Coord_Str (Coord_Str'First .. Colon_Pos - 1));
                           Mea_Tok := Make_Token (Coord_Str (Colon_Pos + 1 .. Coord_Str'Last));
                        else
                           Loc_Tok := Make_Token (Coord_Str);
                        end if;

                        if Loc_Tok.Length = 0 or else Mea_Tok.Length = 0 then
                           Set_Error ("Malformed coordinate in ASSERT record: " & Coord_Str);
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;

                        if Count >= 6 and then Tokens (6).Kind = Tok_Quoted then
                           declare
                              Desc_Str : constant String := Slice (Line, Tokens (6));
                           begin
                              Desc_Tok := Make_Token (Desc_Str);
                           end;
                        end if;

                        --  Check collision with event IDs
                        for E of Result.Events loop
                           if Equal_Token (Id (E).Token, Make_Token (As_Id_Str)) then
                              Set_Error ("ASSERT ID collides with Event ID: " & As_Id_Str);
                              Ada.Text_IO.Close (File);
                              return Result;
                           end if;
                        end loop;

                        Add_Assertion
                          (Result.Assertions,
                           (Id          => (Token => Make_Token (As_Id_Str)),
                            Valid_On    => Parsed_Date,
                            Coordinate  => (Locus   => (Token => Loc_Tok),
                                            Measure => (Token => Mea_Tok)),
                            Amount      => Quanta_Type (Amt_Val),
                            Description => Desc_Tok),
                           Add_Ok);

                        if not Add_Ok then
                           Set_Error ("Duplicate or overflow ASSERT ID: " & As_Id_Str);
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                     end;
                  elsif Tag = "RELATION" then
                     --  Directional claim: RELATION <id> <source-tx>
                     --  <debtor> <creditor> <measure> <amount>. Endpoints are
                     --  `household` or `ext:<name>`; one side must be the
                     --  household and the two sides must differ.
                     if Count /= 7 then
                        Set_Error ("Malformed RELATION record");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Id_Str    : constant String := Slice (Line, Tokens (2));
                        Src_Str   : constant String := Slice (Line, Tokens (3));
                        Debt_Str  : constant String := Slice (Line, Tokens (4));
                        Cred_Str  : constant String := Slice (Line, Tokens (5));
                        Mea_Str   : constant String := Slice (Line, Tokens (6));
                        Amt_Str   : constant String := Slice (Line, Tokens (7));
                        Amt_Val   : Long_Long_Integer;
                        Debtor, Creditor : Relation_Endpoint;
                        Debt_Ok, Cred_Ok : Boolean;
                     begin
                        Parse_Endpoint (Debt_Str, Debtor, Debt_Ok);
                        Parse_Endpoint (Cred_Str, Creditor, Cred_Ok);
                        if Id_Str'Length = 0
                          or else Id_Str'Length > Max_Token_Length
                          or else Src_Str'Length = 0
                          or else Src_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid RELATION identity");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif not Debt_Ok or else not Cred_Ok then
                           Set_Error ("Invalid RELATION endpoint");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Equal_Endpoint (Debtor, Creditor) then
                           Set_Error ("RELATION endpoints must differ");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Debtor.Kind /= Endpoint_Household
                          and then Creditor.Kind /= Endpoint_Household
                        then
                           Set_Error ("RELATION must involve the household");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Mea_Str'Length = 0
                          or else Mea_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid RELATION measure");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif not Parse_Integer (Amt_Str, Amt_Val)
                          or else Amt_Val <= 0
                          or else Amt_Val > Long_Long_Integer (Quanta_Type'Last)
                        then
                           Set_Error ("Invalid RELATION amount");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Rel_Mem.Claim_Count = Max_Relations then
                           Set_Error ("Exceeded maximum relation claims");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        Rel_Mem.Claim_Count := Rel_Mem.Claim_Count + 1;
                        Rel_Mem.Claims (Rel_Mem.Claim_Count) :=
                          (Id       => Make_Token (Id_Str),
                           Source   => (Token => Make_Token (Src_Str)),
                           Debtor   => Debtor,
                           Creditor => Creditor,
                           Measure  => Make_Token (Mea_Str),
                           Face     => Quanta_Type (Amt_Val));
                     end;
                  elsif Tag = "DISCHARGE" then
                     --  Fulfillment provenance: DISCHARGE <settlement-tx>
                     --  <claim-id> <amount>. One row per pair, positive
                     --  amounts; the aggregate bound is checked at admission.
                     if Count /= 4 then
                        Set_Error ("Malformed DISCHARGE record");
                        Ada.Text_IO.Close (File);
                        return Result;
                     end if;

                     declare
                        Stl_Str : constant String := Slice (Line, Tokens (2));
                        Clm_Str : constant String := Slice (Line, Tokens (3));
                        Amt_Str : constant String := Slice (Line, Tokens (4));
                        Amt_Val : Long_Long_Integer;
                     begin
                        if Stl_Str'Length = 0
                          or else Stl_Str'Length > Max_Token_Length
                          or else Clm_Str'Length = 0
                          or else Clm_Str'Length > Max_Token_Length
                        then
                           Set_Error ("Invalid DISCHARGE identity");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif not Parse_Integer (Amt_Str, Amt_Val)
                          or else Amt_Val <= 0
                          or else Amt_Val > Long_Long_Integer (Quanta_Type'Last)
                        then
                           Set_Error ("Invalid DISCHARGE amount");
                           Ada.Text_IO.Close (File);
                           return Result;
                        elsif Rel_Mem.Discharge_Count = Max_Discharges then
                           Set_Error ("Exceeded maximum discharges");
                           Ada.Text_IO.Close (File);
                           return Result;
                        end if;
                        Rel_Mem.Discharge_Count := Rel_Mem.Discharge_Count + 1;
                        Rel_Mem.Discharges (Rel_Mem.Discharge_Count) :=
                          (Settlement => (Token => Make_Token (Stl_Str)),
                           Target     => Make_Token (Clm_Str),
                           Amount     => Quanta_Type (Amt_Val));
                     end;
                  else
                     Set_Error ("Expected 'TX', 'ASSERT', 'RELATION', or 'DISCHARGE' record header, found: " & Tag);
                     Ada.Text_IO.Close (File);
                     return Result;
                  end if;
               end;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);

      --  Assemble encapsulated memory structures
      if Event_Ids_Are_Unique (Val_List) then
         Result.Validities := Make_Validity_Memory (Val_List);
      else
         Set_Error ("Duplicate Event_Id in journal validity facts");
         return Result;
      end if;

      if Event_Ids_Are_Unique (Desc_List) then
         Result.Descriptions := Make_Description_Memory (Desc_List);
      else
         Set_Error ("Duplicate Event_Id in journal description facts");
         return Result;
      end if;

      if not Metadata_Event_Ids_Are_Unique (Meta_List) then
         Set_Error ("Duplicate Event_Id in transaction metadata");
         return Result;
      elsif not Replacement_References_Are_Closed (Meta_List) then
         Set_Error ("Replacement references unknown Event_Id");
         return Result;
      elsif not Replacements_Are_One_To_One (Meta_List) then
         Set_Error ("Replacement history branches");
         return Result;
      elsif not Replacements_Are_Acyclic (Meta_List) then
         Set_Error ("Replacement history contains a cycle");
         return Result;
      elsif not Reversal_References_Are_Closed (Meta_List) then
         Set_Error ("Reversal references unknown Event_Id");
         return Result;
      elsif not Reversals_Are_One_To_One (Meta_List) then
         Set_Error ("Reversal history branches");
         return Result;
      elsif not Reversals_Have_No_Chains (Meta_List) then
         Set_Error ("Reversal chain is not admitted");
         return Result;
      elsif not Reversals_Respect_Replacement (Meta_List) then
         Set_Error ("Reversal and replacement histories conflict");
         return Result;
      elsif not Claim_Ids_Are_Unique (Rel_Mem) then
         Set_Error ("Duplicate relation claim identity");
         return Result;
      elsif not Discharge_Pairs_Are_Unique (Rel_Mem) then
         Set_Error ("Duplicate discharge row");
         return Result;
      end if;
      Result.Metadata := Make_Metadata_Memory (Meta_List);

      --  Relation references resolve against retained events; aggregate
      --  discharges never exceed the claimed face. Both endpoints were
      --  checked pairwise at parse time.
      for I in 1 .. Rel_Mem.Claim_Count loop
         declare
            Found_Source : Boolean := False;
            Total : Long_Long_Integer := 0;
         begin
            for Item of Result.Events loop
               if Equal_Token
                 (Id (Item).Token, Rel_Mem.Claims (I).Source.Token)
               then
                  Found_Source := True;
                  exit;
               end if;
            end loop;
            if not Found_Source then
               Set_Error ("Relation claim references unknown event");
               return Result;
            end if;
            for D in 1 .. Rel_Mem.Discharge_Count loop
               if Equal_Token
                 (Rel_Mem.Discharges (D).Target, Rel_Mem.Claims (I).Id)
               then
                  Total := Total
                    + Long_Long_Integer (Rel_Mem.Discharges (D).Amount);
                  if Total > Long_Long_Integer (Rel_Mem.Claims (I).Face) then
                     Set_Error ("Discharges exceed the claimed face amount");
                     return Result;
                  end if;
               end if;
            end loop;
         end;
      end loop;
      for D in 1 .. Rel_Mem.Discharge_Count loop
         declare
            Found_Stl : Boolean := False;
            Found_Clm : Boolean := False;
         begin
            for Item of Result.Events loop
               if Equal_Token
                 (Id (Item).Token,
                  Rel_Mem.Discharges (D).Settlement.Token)
               then
                  Found_Stl := True;
                  exit;
               end if;
            end loop;
            for I in 1 .. Rel_Mem.Claim_Count loop
               if Equal_Token
                 (Rel_Mem.Claims (I).Id, Rel_Mem.Discharges (D).Target)
               then
                  Found_Clm := True;
                  exit;
               end if;
            end loop;
            if not Found_Stl then
               Set_Error ("Discharge references unknown settlement event");
               return Result;
            elsif not Found_Clm then
               Set_Error ("Discharge references unknown claim");
               return Result;
            end if;
         end;
      end loop;
      Result.Relations := Rel_Mem;

      Result.Success := True;
      return Result;

   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Set_Error ("Unexpected I/O exception reading journal");
         return Result;
   end Read_Journal_File;

end HRA_N.Storage.Journal_Reader;
