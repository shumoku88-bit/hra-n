-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Scheduled_Inspection
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;

package body HRA_N.Application.Scheduled_Inspection is

   function Event_Exists
     (Events : Event_Vectors.Vector;
      Target : Event_Id) return Boolean
   is
   begin
      for Ev of Events loop
         if Equal_Token (Id (Ev).Token, Target.Token) then
            return True;
         end if;
      end loop;
      return False;
   end Event_Exists;

   function Has_Effective_Completion
     (Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector;
      Target    : Scheduled_Id) return Boolean
   is
   begin
      for I in 1 .. Lifecycle.Comp_Count loop
         if Equal_Token (Lifecycle.Comp_Items (I).Scheduled.Token, Target.Token) then
            return Event_Exists (Events, Lifecycle.Comp_Items (I).Actual);
         end if;
      end loop;
      return False;
   end Has_Effective_Completion;

   function Is_Acyclic (Lifecycle : Scheduled_Lifecycle) return Boolean is
   begin
      for I in 1 .. Lifecycle.Repl_Count loop
         declare
            Start_Id : constant Scheduled_Id := Lifecycle.Repl_Items (I).Original;
            Cur      : Scheduled_Id          := Lifecycle.Repl_Items (I).Replaced_By;
         begin
            if Equal_Token (Cur.Token, Start_Id.Token) then
               return False;
            end if;

            for Step in 1 .. Lifecycle.Repl_Count loop
               declare
                  Found_Next : Boolean := False;
               begin
                  for J in 1 .. Lifecycle.Repl_Count loop
                     if Equal_Token (Lifecycle.Repl_Items (J).Original.Token, Cur.Token) then
                        Cur := Lifecycle.Repl_Items (J).Replaced_By;
                        Found_Next := True;
                        exit;
                     end if;
                  end loop;

                  if not Found_Next then
                     exit;
                  end if;

                  if Equal_Token (Cur.Token, Start_Id.Token) then
                     return False;
                  end if;
               end;
            end loop;
         end;
      end loop;
      return True;
   end Is_Acyclic;

   function Current_Open_Scheduled
     (Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector) return Open_Occurrences_Result
   is
      Result : Open_Occurrences_Result;
   begin
      if not Completions_Reference_Known (Lifecycle) then
         Result.Status := Status_Unknown_Completion_Scheduled;
         return Result;
      end if;

      if not Retirements_Reference_Known (Lifecycle) then
         Result.Status := Status_Unknown_Retirement_Scheduled;
         return Result;
      end if;

      if not Replacements_Reference_Known (Lifecycle) then
         Result.Status := Status_Unknown_Replacement_Scheduled;
         return Result;
      end if;

      if not Replacements_Are_One_To_One (Lifecycle) or else not Is_Acyclic (Lifecycle) then
         Result.Status := Status_Invalid_Replacement_Graph;
         return Result;
      end if;

      if not Terminal_Evidence_Compatible (Lifecycle)
        or else not Replacement_Terminal_Compatible (Lifecycle)
      then
         Result.Status := Status_Conflicting_Terminal_Evidence;
         return Result;
      end if;

      for I in 1 .. Lifecycle.Sched_Count loop
         declare
            Occ : constant Scheduled_Occurrence := Lifecycle.Sched_Items (I);
         begin
            if not Is_Retired (Lifecycle, Occ.Id)
              and then not Has_Effective_Completion (Lifecycle, Events, Occ.Id)
              and then not Is_Replaced (Lifecycle, Occ.Id)
            then
               Result.Count := Result.Count + 1;
               Result.Occurrences (Result.Count) := Occ;
            end if;
         end;
      end loop;

      Result.Status := Status_Ok;
      return Result;
   end Current_Open_Scheduled;

   function Query_Day_Evidence
     (Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector;
      Day       : Date_Type) return Day_Evidence_Result
   is
      Open_Res : constant Open_Occurrences_Result :=
        Current_Open_Scheduled (Lifecycle, Events);
      Result   : Day_Evidence_Result;
   begin
      if Open_Res.Status /= Status_Ok then
         Result.Kind   := Evidence_Refused;
         Result.Status := Open_Res.Status;
         return Result;
      end if;

      for I in 1 .. Open_Res.Count loop
         declare
            Occ : constant Scheduled_Occurrence := Open_Res.Occurrences (I);
         begin
            if Equal_Date (Occ.Expected_Day, Day) then
               Result.Count := Result.Count + 1;
               Result.Occurrences (Result.Count) := Occ;
            end if;
         end;
      end loop;

      if Result.Count > 0 then
         Result.Kind   := Evidence_Due;
         Result.Status := Status_Ok;
      else
         Result.Kind   := Evidence_Unknown;
         Result.Status := Status_Ok;
      end if;

      return Result;
   end Query_Day_Evidence;

   function Normalize_Coordinates
     (Coordinates : Balance_Coordinate_List) return Balance_Coordinate_List
   is
      Result : Balance_Coordinate_List;
   begin
      for I in 1 .. Coordinates.Count loop
         declare
            Coord   : constant Coordinate_Type := Coordinates.Values (I);
            Present : Boolean := False;
         begin
            for J in 1 .. Result.Count loop
               if Equal_Coordinate (Result.Values (J), Coord) then
                  Present := True;
                  exit;
               end if;
            end loop;

            if not Present and then Result.Count < Max_Balance_Coordinates then
               Result.Count := Result.Count + 1;
               Result.Values (Result.Count) := Coord;
            end if;
         end;
      end loop;
      return Result;
   end Normalize_Coordinates;

   function Aggregate_Effects
     (Occurrences   : Occurrence_Array;
      Count         : Natural;
      Coordinates   : Balance_Coordinate_List;
      End_Exclusive : Date_Type;
      Suppress_Id   : Scheduled_Id := (Token => (Length => 0, Value => [others => ' '])))
      return Balance_Effects_List
   is
      Normalized : constant Balance_Coordinate_List := Normalize_Coordinates (Coordinates);
      List       : Balance_Effects_List;
   begin
      List.Count := Normalized.Count;
      for C in 1 .. Normalized.Count loop
         declare
            Coord      : constant Coordinate_Type := Normalized.Values (C);
            Quanta_Sum : Quanta_Type              := 0;
         begin
            for I in 1 .. Count loop
               declare
                  Occ : constant Scheduled_Occurrence := Occurrences (I);
               begin
                  if (Suppress_Id.Token.Length = 0
                      or else not Equal_Token (Occ.Id.Token, Suppress_Id.Token))
                    and then Date_Less (Occ.Expected_Day, End_Exclusive)
                    and then Equal_Token (Occ.Measure.Token, Coord.Measure.Token)
                  then
                     declare
                        Amt : constant Quanta_Type := Quantity_At (Occ, Coord.Locus);
                     begin
                        if Amt > 0 and then Quanta_Sum > Max_Quanta_Value - Amt then
                           Quanta_Sum := Max_Quanta_Value;
                        elsif Amt < 0 and then Quanta_Sum < Min_Quanta_Value - Amt then
                           Quanta_Sum := Min_Quanta_Value;
                        else
                           Quanta_Sum := Quanta_Sum + Amt;
                        end if;
                     end;
                  end if;
               end;
            end loop;
            List.Effects (C) := (Coordinate => Coord, Quantity => Quanta_Sum);
         end;
      end loop;
      return List;
   end Aggregate_Effects;

   function Calculate_Balance_Effects
     (Lifecycle     : Scheduled_Lifecycle;
      Events        : Event_Vectors.Vector;
      Coordinates   : Balance_Coordinate_List;
      End_Exclusive : Date_Type) return Balance_Effects_Result
   is
      Open_Res : constant Open_Occurrences_Result :=
        Current_Open_Scheduled (Lifecycle, Events);
      Result   : Balance_Effects_Result;
   begin
      if Open_Res.Status /= Status_Ok then
         Result.Status := Open_Res.Status;
         return Result;
      end if;

      Result.Status  := Status_Ok;
      Result.Effects := Aggregate_Effects
        (Occurrences   => Open_Res.Occurrences,
         Count         => Open_Res.Count,
         Coordinates   => Coordinates,
         End_Exclusive => End_Exclusive);
      return Result;
   end Calculate_Balance_Effects;

   function Compare_Suppression
     (Lifecycle     : Scheduled_Lifecycle;
      Events        : Event_Vectors.Vector;
      Coordinates   : Balance_Coordinate_List;
      End_Exclusive : Date_Type;
      Target_Id     : Scheduled_Id) return Suppression_Comparison_Result
   is
      Open_Res     : constant Open_Occurrences_Result :=
        Current_Open_Scheduled (Lifecycle, Events);
      Result       : Suppression_Comparison_Result;
      Target_Found : Boolean := False;
   begin
      if Open_Res.Status /= Status_Ok then
         Result.Status := Open_Res.Status;
         return Result;
      end if;

      for I in 1 .. Open_Res.Count loop
         if Equal_Token (Open_Res.Occurrences (I).Id.Token, Target_Id.Token) then
            Target_Found := True;
            exit;
         end if;
      end loop;

      if not Target_Found then
         Result.Status := Status_Target_Not_Open;
         return Result;
      end if;

      Result.Status    := Status_Ok;
      Result.Baseline  := Aggregate_Effects
        (Occurrences   => Open_Res.Occurrences,
         Count         => Open_Res.Count,
         Coordinates   => Coordinates,
         End_Exclusive => End_Exclusive);

      Result.Projected := Aggregate_Effects
        (Occurrences   => Open_Res.Occurrences,
         Count         => Open_Res.Count,
         Coordinates   => Coordinates,
         End_Exclusive => End_Exclusive,
         Suppress_Id   => Target_Id);

      return Result;
   end Compare_Suppression;

end HRA_N.Application.Scheduled_Inspection;
