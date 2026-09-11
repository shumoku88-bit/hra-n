-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Reconciliation_Query
-------------------------------------------------------------------------------

with HRA_N.Core.Assertion; use HRA_N.Core.Assertion;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;

package body HRA_N.Application.Reconciliation_Query is

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

   function Row_Less (Left, Right : Reconciliation_Row) return Boolean is
   begin
      if Left.Valid_On /= Right.Valid_On then
         return Date_Less_Or_Equal (Left.Valid_On, Right.Valid_On);
      end if;
      return Token_Less (Left.Assertion_Id, Right.Assertion_Id);
   end Row_Less;

   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config)
      return Reconciliation_View
   is
      Result : Reconciliation_View;

      procedure Fail (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Result.Diagnostic'Length);
      begin
         Result.Status := Frontend_Types.Query_Rejected;
         Result.Diagnostic_Len := L;
         Result.Diagnostic (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Fail;

   begin
      if not Paths.Resolution_Ok then
         Fail ("reconciliation query requires a resolvable household path");
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
      begin
         if not J_Res.Success then
            Fail ("cannot read journal for reconciliation query: " &
                  J_Res.Error_Reason (1 .. J_Res.Error_Len));
            return Result;
         end if;

         Result.Total_Count := J_Res.Assertions.Count;

         for I in 1 .. J_Res.Assertions.Count loop
            declare
               A        : constant Balance_Assertion := J_Res.Assertions.Values (I);
               Loc      : constant Token_Text := A.Coordinate.Locus.Token;
               Mea      : constant Token_Text := A.Coordinate.Measure.Token;
               Computed : Long_Long_Integer := 0;
            begin
               --  Compute sum of effects on or before A.Valid_On
               for E of J_Res.Events loop
                  declare
                     Succ          : Event_Id;
                     Is_Superseded : Boolean := False;
                  begin
                     Find_Successor (J_Res.Metadata, Id (E), Succ, Is_Superseded);
                     if not Is_Superseded then
                        declare
                           Ev_Date : Date_Type;
                           Found_D : Boolean := False;
                        begin
                           Find_Occurrence_Date (J_Res.Validities, Id (E), Ev_Date, Found_D);
                           if Found_D and then Date_Less_Or_Equal (Ev_Date, A.Valid_On) then
                              for K in 1 .. Effect_Count (E) loop
                                 declare
                                    Eff : constant Effect := Effect_At (E, K);
                                 begin
                                    if Equal_Token (Eff.Locus.Token, Loc)
                                      and then Equal_Token (Eff.Measure.Token, Mea)
                                    then
                                       Computed := Computed +
                                         Long_Long_Integer (Eff.Amount.Quanta);
                                    end if;
                                 end;
                              end loop;
                           end if;
                        end;
                     end if;
                  end;
               end loop;

               declare
                  Diff_Val   : constant Long_Long_Integer :=
                    Long_Long_Integer (A.Amount) - Computed;
                  Matched    : constant Boolean := (Diff_Val = 0);
               begin
                  if Matched then
                     Result.Matched_Count := Result.Matched_Count + 1;
                  else
                     Result.Mismatched_Count := Result.Mismatched_Count + 1;
                  end if;

                  if Result.Row_Count < Max_Reconciliation_Rows then
                     Result.Row_Count := Result.Row_Count + 1;
                     Result.Rows (Result.Row_Count) :=
                       (Assertion_Id    => A.Id.Token,
                        Valid_On        => A.Valid_On,
                        Coordinate      => A.Coordinate,
                        Asserted_Amount => A.Amount,
                        Computed_Amount => Computed,
                        Diff            => Diff_Val,
                        Is_Matched      => Matched,
                        Description     => A.Description);
                  end if;
               end;
            end;
         end loop;

         --  Sort rows deterministically
         for I in 2 .. Result.Row_Count loop
            declare
               Key : constant Reconciliation_Row := Result.Rows (I);
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

      return Result;
   end Execute;

end HRA_N.Application.Reconciliation_Query;
