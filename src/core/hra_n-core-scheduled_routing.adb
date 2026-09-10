-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled_Routing
-------------------------------------------------------------------------------

package body HRA_N.Core.Scheduled_Routing with
  SPARK_Mode => On
is

   procedure Find_Current_Route
     (History   : Routing_History;
      Scheduled : Scheduled_Id;
      Locus     : Locus_Id;
      As_Of     : Date_Type;
      Result    : out Route_Result)
   is
      Found : Boolean := False;
      Latest : Date_Type := (Year => 2026, Month => 1, Day => 1);
   begin
      Result := (others => <>);
      for I in 1 .. History.Count loop
         declare
            Candidate : constant Scheduled_Route := History.Entries (I);
         begin
            if Equal_Token (Candidate.Scheduled.Token, Scheduled.Token)
              and then Equal_Token (Candidate.Locus.Token, Locus.Token)
              and then Date_Less_Or_Equal (Candidate.Effective_On, As_Of)
              and then (not Found or else Date_Greater (Candidate.Effective_On, Latest))
            then
               Found := True;
               Latest := Candidate.Effective_On;
               Result.Effective_On := Candidate.Effective_On;
               Result.Purpose := Candidate.Purpose;
               Result.State :=
                 (if Candidate.Managed then Route_Managed else Route_Unmanaged);
            end if;
         end;
      end loop;
   end Find_Current_Route;

end HRA_N.Core.Scheduled_Routing;
