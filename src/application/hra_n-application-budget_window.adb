-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Budget_Window
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;

package body HRA_N.Application.Budget_Window is

   function Date_Strict_Before
     (Y1, M1, D1 : Natural;
      Y2, M2, D2 : Natural) return Boolean is
   begin
      if Y1 < Y2 then
         return True;
      elsif Y1 > Y2 then
         return False;
      elsif M1 < M2 then
         return True;
      elsif M1 > M2 then
         return False;
      else
         return D1 < D2;
      end if;
   end Date_Strict_Before;

   function In_Half_Open
     (Y, M, D    : Natural;
      SY, SM, SD : Natural;
      EY, EM, ED : Natural) return Boolean is
   begin
      --  Start <= (Y, M, D) and then (Y, M, D) < End
      return not Date_Strict_Before (Y, M, D, SY, SM, SD)
        and then Date_Strict_Before (Y, M, D, EY, EM, ED);
   end In_Half_Open;

   procedure Project_Budget_Window
     (Capacity_Mem : Capacity_Memory;
      Events       : Event_Vectors.Vector;
      Validities   : Validity_Memory;
      Routing      : Routing_Map;
      Start_Y      : Natural;
      Start_M      : Natural;
      Start_D      : Natural;
      End_Y        : Natural;
      End_M        : Natural;
      End_D        : Natural;
      Report       : out Budget_Window_Report)
   is
      function Find_Or_Add_Purpose
        (Purp : Token_Text;
         Idx  : out Natural) return Boolean
      is
      begin
         Idx := 0;
         for I in 1 .. Report.Row_Count loop
            if Equal_Token (Report.Rows (I).Purpose, Purp) then
               Idx := I;
               return True;
            end if;
         end loop;

         if Report.Row_Count < Max_Window_Purposes then
            Report.Row_Count := Report.Row_Count + 1;
            Report.Rows (Report.Row_Count) :=
              (Purpose     => Purp,
               Entitlement => Zero_Quanta,
               Consumption => Zero_Quanta,
               Remaining   => Zero_Quanta);
            Idx := Report.Row_Count;
            return True;
         end if;
         return False;
      end Find_Or_Add_Purpose;

      Dummy_Idx : Natural;
   begin
      Report :=
        (Start_Year        => Start_Y,
         Start_Month       => Start_M,
         Start_Day         => Start_D,
         End_Year          => End_Y,
         End_Month         => End_M,
         End_Day           => End_D,
         Row_Count         => 0,
         Rows              => [others => Empty_Envelope_Row],
         Unallocated_Funds => Zero_Quanta,
         Total_Entitlement => Zero_Quanta,
         Total_Consumption => Zero_Quanta,
         Total_Remaining   => Zero_Quanta,
         Capacity_Sum      => 0,
         Movements_Count   => Capacity_Mem.Movement_Count,
         Events_Considered => Natural (Events.Length));

      --  1. Discover remembered purposes in order of appearance in CapacityMemory
      for I in 1 .. Capacity_Mem.Movement_Count loop
         declare
            Mov : constant Capacity_Movement := Capacity_Mem.Movements (I);
         begin
            for C in 1 .. Mov.Change_Count loop
               if Mov.Changes (C).Coord.Kind = Coord_Purpose then
                  if not Find_Or_Add_Purpose (Mov.Changes (C).Coord.Purpose, Dummy_Idx) then
                     null; -- capacity purposes bound reached
                  end if;
               end if;
            end loop;
         end;
      end loop;

      --  2. Project Entitlements from Capacity movements effective in [Start, End)
      for I in 1 .. Capacity_Mem.Movement_Count loop
         declare
            Mov : constant Capacity_Movement := Capacity_Mem.Movements (I);
            EY, EM, ED : Natural;
            Found_Eff  : Boolean;
         begin
            Find_Effective_Date (Capacity_Mem, Mov.Id, EY, EM, ED, Found_Eff);
            if Found_Eff then
               if In_Half_Open (EY, EM, ED, Start_Y, Start_M, Start_D, End_Y, End_M, End_D) then
                  --  Account for Unallocated
                  declare
                     Unalloc_Q : constant Quanta_Type :=
                       Quantity_At (Mov, Make_Unallocated_Coordinate);
                  begin
                     Report.Unallocated_Funds := Report.Unallocated_Funds + Unalloc_Q;
                  end;

                  --  Account for each Purpose
                  for P in 1 .. Report.Row_Count loop
                     declare
                        Purp_Q : constant Quanta_Type :=
                          Quantity_At (Mov, Make_Purpose_Coordinate (Report.Rows (P).Purpose));
                     begin
                        Report.Rows (P).Entitlement :=
                          Report.Rows (P).Entitlement + Purp_Q;
                     end;
                  end loop;
               end if;
            end if;
         end;
      end loop;

      --  3. Project Actual Consumption from Events valid in [Start, End)
      for Cursor in Events.Iterate loop
         declare
            Ev       : constant Event := Event_Vectors.Element (Cursor);
            Has_Val  : Boolean;
            Val_Date : Date_Type;
         begin
            Find_Occurrence_Date (Validities, Id (Ev), Val_Date, Has_Val);
            if Has_Val
              and then In_Half_Open
                         (Val_Date.Year, Val_Date.Month, Val_Date.Day,
                          Start_Y, Start_M, Start_D,
                          End_Y, End_M, End_D)
            then
               for Eff_Idx in 1 .. Effect_Count (Ev) loop
                  declare
                     Eff : constant Effect := Effect_At (Ev, Eff_Idx);
                  begin
                     --  Must match measure JPY
                     if Eff.Measure.Token.Length = 3
                       and then Eff.Measure.Token.Value (1 .. 3) = "jpy"
                     then
                        declare
                           Target_Purp : Token_Text;
                           Found_Purp  : Boolean;
                        begin
                           Find_Purpose (Routing, Eff.Locus, Target_Purp, Found_Purp);
                           if Found_Purp then
                              for P in 1 .. Report.Row_Count loop
                                 if Equal_Token (Report.Rows (P).Purpose, Target_Purp) then
                                    Report.Rows (P).Consumption :=
                                      Report.Rows (P).Consumption + Eff.Amount.Quanta;
                                    exit;
                                 end if;
                              end loop;
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      --  4. Derive Remaining and Subtotals (Lean Observation 181)
      for P in 1 .. Report.Row_Count loop
         Report.Rows (P).Remaining :=
           Report.Rows (P).Entitlement - Report.Rows (P).Consumption;

         Report.Total_Entitlement :=
           Report.Total_Entitlement + Report.Rows (P).Entitlement;
         Report.Total_Consumption :=
           Report.Total_Consumption + Report.Rows (P).Consumption;
         Report.Total_Remaining :=
           Report.Total_Remaining + Report.Rows (P).Remaining;
      end loop;

      Report.Capacity_Sum :=
        Long_Long_Integer (Report.Total_Entitlement) +
        Long_Long_Integer (Report.Unallocated_Funds);
   end Project_Budget_Window;

end HRA_N.Application.Budget_Window;
