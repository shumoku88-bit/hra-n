-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Scheduled_Commitment
-------------------------------------------------------------------------------

with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Event; use HRA_N.Core.Event;

package body HRA_N.Application.Scheduled_Commitment is

   function Event_Exists
     (Events : Event_Vectors.Vector; Target : Event_Id) return Boolean is
   begin
      for Ev of Events loop
         if Equal_Token (Id (Ev).Token, Target.Token) then
            return True;
         end if;
      end loop;
      return False;
   end Event_Exists;

   procedure Add_Quantity
     (Total : in out Quanta_Type; Amount : Quanta_Type; Ok : in out Boolean) is
   begin
      if not Can_Add (Total, Amount) then
         Ok := False;
      else
         Total := Total + Amount;
      end if;
   end Add_Quantity;

   procedure Add_Managed
     (Report : in out Commitment_Report;
      Purpose : Token_Text;
      Amount : Quanta_Type)
   is
      Ok : Boolean := True;
   begin
      for I in 1 .. Report.Managed_Count loop
         if Equal_Token (Report.Managed (I).Purpose, Purpose) then
            Add_Quantity (Report.Managed (I).Quantity, Amount, Ok);
            Add_Quantity (Report.Managed_Total, Amount, Ok);
            Report.Resolved := Report.Resolved and Ok;
            return;
         end if;
      end loop;
      if Report.Managed_Count = Max_Managed_Purposes then
         Report.Resolved := False;
         return;
      end if;
      Report.Managed_Count := Report.Managed_Count + 1;
      Report.Managed (Report.Managed_Count) :=
        (Purpose => Purpose, Quantity => Amount);
      Add_Quantity (Report.Managed_Total, Amount, Ok);
      Report.Resolved := Report.Resolved and Ok;
   end Add_Managed;

   procedure Project
     (Lifecycle    : Scheduled_Lifecycle;
      Events       : Event_Vectors.Vector;
      Roles        : Role_Map;
      Routing      : Routing_History;
      Measure      : Measure_Id;
      Observed_At  : Date_Type;
      End_Exclusive: Date_Type;
      Report       : out Commitment_Report)
   is
   begin
      Report := (others => <>);
      if not Coordinates_Are_Unique (Routing)
        or else not Date_Less (Observed_At, End_Exclusive)
      then
         Report.Resolved := False;
         return;
      end if;

      --  Completion becomes terminal only through an acquired Event authority.
      for I in 1 .. Lifecycle.Comp_Count loop
         if not Event_Exists (Events, Lifecycle.Comp_Items (I).Actual) then
            Report.Resolved := False;
            return;
         end if;
      end loop;

      for S in 1 .. Lifecycle.Sched_Count loop
         declare
            Occ : constant Scheduled_Occurrence := Lifecycle.Sched_Items (S);
            Terminal_Count : Natural := 0;
         begin
            if Is_Completed (Lifecycle, Occ.Id) then Terminal_Count := Terminal_Count + 1; end if;
            if Is_Retired (Lifecycle, Occ.Id) then Terminal_Count := Terminal_Count + 1; end if;
            if Is_Replaced (Lifecycle, Occ.Id) then Terminal_Count := Terminal_Count + 1; end if;
            if Terminal_Count > 1 then
               Report.Resolved := False;
               return;
            end if;

            if Is_Current_Open (Lifecycle, Occ.Id) then
               Report.Open_Occurrences := Report.Open_Occurrences + 1;
               if Equal_Token (Occ.Measure.Token, Measure.Token)
                 and then Date_Less_Or_Equal (Observed_At, Occ.Expected_Day)
                 and then Date_Less (Occ.Expected_Day, End_Exclusive)
               then
                  for C in 1 .. Occ.Changes.Count loop
                     declare
                        Locus : constant Locus_Id := Occ.Changes.Values (C).Locus;
                        First_For_Locus : Boolean := True;
                        Aggregate : Quanta_Type := Zero_Quanta;
                        Ok : Boolean := True;
                     begin
                        for P in 1 .. C - 1 loop
                           if Equal_Token
                             (Occ.Changes.Values (P).Locus.Token, Locus.Token)
                           then
                              First_For_Locus := False;
                           end if;
                        end loop;
                        if First_For_Locus then
                           for J in 1 .. Occ.Changes.Count loop
                              if Equal_Token
                                (Occ.Changes.Values (J).Locus.Token, Locus.Token)
                              then
                                 Add_Quantity
                                   (Aggregate, Occ.Changes.Values (J).Amount, Ok);
                              end if;
                           end loop;
                           if not Ok then
                              Report.Resolved := False;
                              return;
                           end if;
                           if Aggregate > 0 then
                              Report.Selected_Coordinates :=
                                Report.Selected_Coordinates + 1;
                              declare
                                 Route : Route_Result;
                                 Role : Accounting_Role;
                                 Has_Role : Boolean;
                              begin
                                 Find_Current_Route
                                   (Routing, Occ.Id, Locus, Observed_At, Route);
                                 case Route.State is
                                    when Route_Managed =>
                                       Add_Managed (Report, Route.Purpose, Aggregate);
                                    when Route_Unmanaged =>
                                       Add_Quantity (Report.Unmanaged, Aggregate, Report.Resolved);
                                    when Route_Unknown =>
                                       Find_Role (Roles, Locus, Role, Has_Role);
                                       if not Has_Role then
                                          Add_Quantity
                                            (Report.Unresolved_Eligibility, Aggregate,
                                             Report.Resolved);
                                       elsif Role in Role_Expense | Role_Liability then
                                          Add_Quantity
                                            (Report.Unrouted, Aggregate, Report.Resolved);
                                       end if;
                                 end case;
                              end;
                           end if;
                        end if;
                     end;
                  end loop;
               end if;
            end if;
         end;
      end loop;
   end Project;
end HRA_N.Application.Scheduled_Commitment;
