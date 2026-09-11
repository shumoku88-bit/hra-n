-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Balance_Query
-------------------------------------------------------------------------------

with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Assertion; use HRA_N.Core.Assertion;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Balance_Query is

   function Date_Less_Or_Equal (Left, Right : Date_Type) return Boolean is
   begin
      if Left.Year /= Right.Year then
         return Left.Year < Right.Year;
      elsif Left.Month /= Right.Month then
         return Left.Month < Right.Month;
      else
         return Left.Day <= Right.Day;
      end if;
   end Date_Less_Or_Equal;

   function Role_Rank (Row : Balance_Row) return Natural is
   begin
      if not Row.Has_Role then
         return 6;
      end if;
      return (case Row.Role is
                when Role_Asset     => 1,
                when Role_Liability => 2,
                when Role_Equity    => 3,
                when Role_Income    => 4,
                when Role_Expense   => 5);
   end Role_Rank;

   function Row_Less (Left, Right : Balance_Row) return Boolean is
      Left_Rank  : constant Natural := Role_Rank (Left);
      Right_Rank : constant Natural := Role_Rank (Right);
   begin
      if Left_Rank /= Right_Rank then
         return Left_Rank < Right_Rank;
      end if;
      declare
         Left_Loc  : constant String := Left.Locus.Value (1 .. Left.Locus.Length);
         Right_Loc : constant String := Right.Locus.Value (1 .. Right.Locus.Length);
      begin
         if Left_Loc /= Right_Loc then
            return Left_Loc < Right_Loc;
         end if;
      end;
      declare
         Left_Mea  : constant String := Left.Measure.Value (1 .. Left.Measure.Length);
         Right_Mea : constant String := Right.Measure.Value (1 .. Right.Measure.Length);
      begin
         return Left_Mea < Right_Mea;
      end;
   end Row_Less;

   function Execute
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Request : Query := (Scope => Scope_All, Has_As_Of => False, As_Of_Date => (2026, 1, 1)))
      return Balance_View
   is
      Result : Balance_View;

      procedure Fail (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Result.Diagnostic'Length);
      begin
         Result.Status := Frontend_Types.Query_Rejected;
         Result.Diagnostic_Len := L;
         Result.Diagnostic (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Fail;

   begin
      Result.Scope := Request.Scope;
      Result.Has_As_Of := Request.Has_As_Of;
      Result.As_Of_Date := Request.As_Of_Date;

      if not Paths.Resolution_Ok then
         Fail ("balance query requires a resolvable household path");
         return Result;
      end if;

      Result.Snapshot :=
        (if Paths.Is_Versioned
         then (Kind     => Frontend_Types.Snapshot_Versioned,
               Identity => Make_Token (Path_Resolver.Snapshot_Id_Str (Paths)))
         else (Kind     => Frontend_Types.Snapshot_Unversioned));

      declare
         J_Res : constant Journal_Result :=
           Read_Journal_File (Path_Resolver.Journal_Path_Str (Paths));
         P_Res : constant Policy_Result :=
           Read_Policy_File (Path_Resolver.Policy_Path_Str (Paths));
      begin
         if not J_Res.Success then
            Fail ("cannot read journal for balance query: " &
                  J_Res.Error_Reason (1 .. J_Res.Error_Len));
            return Result;
         elsif not P_Res.Success then
            Fail ("cannot read policy for balance query: " &
                  P_Res.Error_Reason (1 .. P_Res.Error_Len));
            return Result;
         end if;

         --  Accumulate distinct coordinates
         declare
            type Coord_Pair is record
               Locus   : Token_Text;
               Measure : Token_Text;
            end record;

            Coords      : array (1 .. Max_Balance_Rows) of Coord_Pair;
            Coord_Count : Natural := 0;

            procedure Add_Coord (Loc, Mea : Token_Text) is
            begin
               if Loc.Length = 0 or else Mea.Length = 0 then
                  return;
               end if;
               for I in 1 .. Coord_Count loop
                  if Equal_Token (Coords (I).Locus, Loc)
                    and then Equal_Token (Coords (I).Measure, Mea)
                  then
                     return;
                  end if;
               end loop;
               if Coord_Count < Max_Balance_Rows then
                  Coord_Count := Coord_Count + 1;
                  Coords (Coord_Count) := (Locus => Loc, Measure => Mea);
               end if;
            end Add_Coord;

         begin
            --  1. Coordinates from Zero-Origin coverage in Policy
            for I in 1 .. Coordinate_Count (P_Res.Coverage) loop
               declare
                  C : constant Coordinate_Type := Coordinate_At (P_Res.Coverage, I);
               begin
                  Add_Coord (C.Locus.Token, C.Measure.Token);
               end;
            end loop;

            --  2. Coordinates from active transactions in Journal
            for E of J_Res.Events loop
               declare
                  Succ          : Event_Id;
                  Is_Superseded : Boolean := False;
               begin
                  Find_Successor (J_Res.Metadata, Id (E), Succ, Is_Superseded);
                  if not Is_Superseded then
                     for I in 1 .. Effect_Count (E) loop
                        declare
                           Eff : constant Effect := Effect_At (E, I);
                        begin
                           Add_Coord (Eff.Locus.Token, Eff.Measure.Token);
                        end;
                     end loop;
                  end if;
               end;
            end loop;

            --  3. Coordinates from Balance Assertions in Journal
            for I in 1 .. J_Res.Assertions.Count loop
               declare
                  A : constant Balance_Assertion := J_Res.Assertions.Values (I);
               begin
                  Add_Coord (A.Coordinate.Locus.Token, A.Coordinate.Measure.Token);
               end;
            end loop;

            --  Now compute balance and attributes for each coordinate
            for C in 1 .. Coord_Count loop
               declare
                  Loc : constant Token_Text := Coords (C).Locus;
                  Mea : constant Token_Text := Coords (C).Measure;
                  Bal : Long_Long_Integer := 0;
                  Cnt : Natural := 0;

                  Has_Role_Val : Boolean := False;
                  Role_Val     : Accounting_Role := Role_Asset;

                  Is_Known : constant Boolean :=
                    Is_Covered
                      (P_Res.Coverage,
                       (Locus => (Token => Loc), Measure => (Token => Mea)));
               begin
                  --  Compute sum of effects from active unsuperseded transactions
                  for E of J_Res.Events loop
                     declare
                        Succ          : Event_Id;
                        Is_Superseded : Boolean := False;
                     begin
                        Find_Successor (J_Res.Metadata, Id (E), Succ, Is_Superseded);
                        if not Is_Superseded then
                           declare
                              Date_Ok : Boolean := True;
                           begin
                              if Request.Has_As_Of then
                                 declare
                                    Ev_Date : Date_Type;
                                    Found   : Boolean := False;
                                 begin
                                    Find_Occurrence_Date
                                      (J_Res.Validities, Id (E), Ev_Date, Found);
                                    if Found then
                                       Date_Ok :=
                                         Date_Less_Or_Equal (Ev_Date, Request.As_Of_Date);
                                    else
                                       Date_Ok := False;
                                    end if;
                                 end;
                              end if;

                              if Date_Ok then
                                 for I in 1 .. Effect_Count (E) loop
                                    declare
                                       Eff : constant Effect := Effect_At (E, I);
                                    begin
                                       if Equal_Token (Eff.Locus.Token, Loc)
                                         and then Equal_Token (Eff.Measure.Token, Mea)
                                       then
                                          Bal := Bal + Long_Long_Integer (Eff.Amount.Quanta);
                                          Cnt := Cnt + 1;
                                       end if;
                                    end;
                                 end loop;
                              end if;
                           end;
                        end if;
                     end;
                  end loop;

                  --  Evaluate assertion conflicts
                  declare
                     Has_Conflict : Boolean := False;
                  begin
                     for A_Idx in 1 .. J_Res.Assertions.Count loop
                        declare
                           A : constant Balance_Assertion := J_Res.Assertions.Values (A_Idx);
                        begin
                           if Equal_Token (A.Coordinate.Locus.Token, Loc)
                             and then Equal_Token (A.Coordinate.Measure.Token, Mea)
                           then
                              declare
                                 Check_Assertion : Boolean := True;
                              begin
                                 if Request.Has_As_Of then
                                    Check_Assertion :=
                                      Date_Less_Or_Equal (A.Valid_On, Request.As_Of_Date);
                                 end if;

                                 if Check_Assertion then
                                    declare
                                       Assert_Bal : Long_Long_Integer := 0;
                                    begin
                                       for E of J_Res.Events loop
                                          declare
                                             Succ          : Event_Id;
                                             Is_Superseded : Boolean := False;
                                          begin
                                             Find_Successor
                                               (J_Res.Metadata, Id (E), Succ, Is_Superseded);
                                             if not Is_Superseded then
                                                declare
                                                   Ev_Date : Date_Type;
                                                   Found_D : Boolean := False;
                                                begin
                                                   Find_Occurrence_Date
                                                     (J_Res.Validities, Id (E), Ev_Date, Found_D);
                                                   if Found_D
                                                     and then Date_Less_Or_Equal (Ev_Date, A.Valid_On)
                                                   then
                                                      for I in 1 .. Effect_Count (E) loop
                                                         declare
                                                            Eff : constant Effect := Effect_At (E, I);
                                                         begin
                                                            if Equal_Token (Eff.Locus.Token, Loc)
                                                              and then Equal_Token (Eff.Measure.Token, Mea)
                                                            then
                                                               Assert_Bal := Assert_Bal +
                                                                 Long_Long_Integer (Eff.Amount.Quanta);
                                                            end if;
                                                         end;
                                                      end loop;
                                                   end if;
                                                end;
                                             end if;
                                          end;
                                       end loop;

                                       if Assert_Bal /= Long_Long_Integer (A.Amount) then
                                          Has_Conflict := True;
                                       end if;
                                    end;
                                 end if;
                              end;
                           end if;
                        end;
                     end loop;

                     --  Determine role
                     Find_Role (P_Res.Roles, (Token => Loc), Role_Val, Has_Role_Val);

                     declare
                        Status_Val : constant Balance_Epistemic_Status :=
                          (if Has_Conflict then Status_Conflict
                           elsif Is_Known then Status_Known_Zero
                           else Status_Unknown_Origin);
                     begin
                        --  Update aggregate summary counts
                        if Has_Conflict then
                           Result.Total_Conflict_Count := Result.Total_Conflict_Count + 1;
                        elsif Is_Known then
                           Result.Total_Known_Count := Result.Total_Known_Count + 1;
                        else
                           Result.Total_Unknown_Count := Result.Total_Unknown_Count + 1;
                        end if;

                  --  Filter according to scope
                  declare
                     Include : Boolean := True;
                  begin
                     if Request.Scope = Scope_Known_Only and then not Is_Known then
                        Include := False;
                     elsif Request.Scope = Scope_Unknown_Only and then Is_Known then
                        Include := False;
                     end if;

                     if Include and then Result.Row_Count < Max_Balance_Rows then
                        Result.Row_Count := Result.Row_Count + 1;
                        Result.Rows (Result.Row_Count) :=
                          (Locus            => Loc,
                           Measure          => Mea,
                           Has_Role         => Has_Role_Val,
                           Role             => Role_Val,
                           Epistemic_Status => Status_Val,
                           Amount           => Bal,
                           Posting_Count    => Cnt);
                     end if;
                  end;
               end;
            end;
         end;
      end loop;

            --  Sort rows deterministically
            for I in 2 .. Result.Row_Count loop
               declare
                  Key : constant Balance_Row := Result.Rows (I);
                  J   : Natural := I - 1;
               begin
                  while J > 0 and then Row_Less (Key, Result.Rows (J)) loop
                     Result.Rows (J + 1) := Result.Rows (J);
                     J := J - 1;
                  end loop;
                  Result.Rows (J + 1) := Key;
               end;
            end loop;

            Result.Status := Frontend_Types.Query_Complete;
         end;
      end;

      return Result;
   end Execute;

end HRA_N.Application.Balance_Query;
