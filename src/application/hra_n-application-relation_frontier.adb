-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Relation_Frontier
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;

package body HRA_N.Application.Relation_Frontier is

   function Same_Event (Left, Right : Event_Id) return Boolean is
     (Equal_Token (Left.Token, Right.Token));

   function Same_Source (Left, Right : Relation_Unit) return Boolean is
     (Same_Event (Left.Source_Event, Right.Source_Event)
      and then Equal_Token (Left.Source_Effect.Token, Right.Source_Effect.Token));

   function Event_Exists
     (Events : Event_Vectors.Vector;
      Id     : Event_Id) return Boolean
   is
   begin
      for Ev of Events loop
         if Same_Event (HRA_N.Core.Event.Id (Ev), Id) then
            return True;
         end if;
      end loop;
      return False;
   end Event_Exists;

   procedure Find_Source_Effect
     (Events : Event_Vectors.Vector;
      Unit   : Relation_Unit;
      Value  : out Effect;
      Found  : out Boolean)
   is
   begin
      Value := Empty_Effect;
      Found := False;
      for Ev of Events loop
         if Same_Event (HRA_N.Core.Event.Id (Ev), Unit.Source_Event) then
            for I in 1 .. Effect_Count (Ev) loop
               declare
                  Candidate : constant Effect := Effect_At (Ev, I);
               begin
                  if Equal_Token
                       (Candidate.Key.Token, Unit.Source_Effect.Token)
                  then
                     Value := Candidate;
                     Found := True;
                     return;
                  end if;
               end;
            end loop;
            return;
         end if;
      end loop;
   end Find_Source_Effect;

   function Magnitude (Value : Quanta_Type) return Quanta_Type is
     (if Value < 0 then -Value else Value);

   function Source_Units_Are_Admissible
     (Units            : Unit_Memory;
      Target           : Relation_Unit;
      Source_Magnitude : Quanta_Type) return Boolean
   is
      Total : Quanta_Type := Zero_Quanta;
   begin
      for I in 1 .. Units.Count loop
         declare
            Unit : constant Relation_Unit := Units.Units (I);
         begin
            if Same_Source (Unit, Target) then
               if not Endpoints_Are_Admissible (Unit.Debtor, Unit.Creditor)
                 or else Unit.Quantity <= 0
                 or else Unit.Quantity > Source_Magnitude
                 or else Unit.Quantity > Source_Magnitude - Total
               then
                  return False;
               end if;
               Total := Total + Unit.Quantity;
            end if;
         end;
      end loop;
      return True;
   end Source_Units_Are_Admissible;

   function Active_Discharge_Events_Are_Unique
     (Events     : Event_Vectors.Vector;
      Discharges : Discharge_Memory;
      Target_Id  : Token_Text) return Boolean
   is
   begin
      for I in 1 .. Discharges.Count loop
         if Equal_Token (Discharges.Discharges (I).Target, Target_Id)
           and then Event_Exists (Events, Discharges.Discharges (I).Event)
         then
            for J in I + 1 .. Discharges.Count loop
               if Equal_Token (Discharges.Discharges (J).Target, Target_Id)
                 and then Event_Exists (Events, Discharges.Discharges (J).Event)
                 and then Same_Event
                   (Discharges.Discharges (I).Event,
                    Discharges.Discharges (J).Event)
               then
                  return False;
               end if;
            end loop;
         end if;
      end loop;
      return True;
   end Active_Discharge_Events_Are_Unique;

   procedure Project_Outstanding
     (Events     : Event_Vectors.Vector;
      Units      : Unit_Memory;
      Discharges : Discharge_Memory;
      Target_Id  : Token_Text;
      Result     : out Outstanding_Result)
   is
      Target : Relation_Unit;
      Found  : Boolean;
      Source : Effect;
      Total  : Quanta_Type := Zero_Quanta;
      Count  : Natural     := 0;
   begin
      Result := (others => <>);

      --  Duplicate raw unit identity makes retained provenance ambiguous,
      --  even when list order would otherwise offer a first match.
      if not Unit_Ids_Are_Unique (Units) then
         Result.State := Evidence_Unresolved;
         return;
      end if;

      Find_Unit (Units, Target_Id, Target, Found);
      if not Found then
         Result.State := Target_Absent;
         return;
      end if;

      Find_Source_Effect (Events, Target, Source, Found);
      if not Found then
         Result.State := Evidence_Unresolved;
         return;
      end if;

      if not Source_Units_Are_Admissible
        (Units, Target, Magnitude (Source.Amount.Quanta))
      then
         Result.State := Evidence_Unresolved;
         return;
      end if;

      if not Active_Discharge_Events_Are_Unique
        (Events, Discharges, Target_Id)
      then
         Result.State := Evidence_Unresolved;
         return;
      end if;

      for I in 1 .. Discharges.Count loop
         declare
            Discharge : constant Relation_Discharge :=
              Discharges.Discharges (I);
         begin
            if Equal_Token (Discharge.Target, Target_Id)
              and then Event_Exists (Events, Discharge.Event)
            then
               if Same_Event (Discharge.Event, Target.Source_Event)
                 or else Discharge.Quantity <= 0
                 or else Discharge.Quantity > Target.Quantity
                 or else Discharge.Quantity > Target.Quantity - Total
               then
                  Result.State := Evidence_Unresolved;
                  return;
               end if;
               Total := Total + Discharge.Quantity;
               Count := Count + 1;
            end if;
         end;
      end loop;

      Result.Original_Quantity        := Target.Quantity;
      Result.Discharged_Quantity      := Total;
      Result.Outstanding_Quantity     := Target.Quantity - Total;
      Result.Admitted_Discharge_Count := Count;
      Result.Measure                  := Source.Measure;
      Result.State :=
        (if Result.Outstanding_Quantity = 0
         then Relation_Discharged
         else Relation_Open);
   end Project_Outstanding;

end HRA_N.Application.Relation_Frontier;
