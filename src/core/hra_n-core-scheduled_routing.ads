-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Scheduled_Routing
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Core.Scheduled_Routing with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Scheduled_Routes : constant := 256;
   subtype Route_Count_Type is Natural range 0 .. Max_Scheduled_Routes;
   subtype Route_Index_Type is Positive range 1 .. Max_Scheduled_Routes;

   type Scheduled_Route is record
      Scheduled   : Scheduled_Id;
      Locus       : Locus_Id;
      Effective_On: Date_Type;
      Managed     : Boolean := False;
      Purpose     : Token_Text;
   end record;

   Empty_Route : constant Scheduled_Route :=
     (Scheduled    => (Token => (Length => 0, Value => [others => ' '])),
      Locus        => (Token => (Length => 0, Value => [others => ' '])),
      Effective_On => (Year => 2026, Month => 1, Day => 1),
      Managed      => False,
      Purpose      => (Length => 0, Value => [others => ' ']));

   type Route_Array is array (Route_Index_Type) of Scheduled_Route;
   type Routing_History is record
      Count   : Route_Count_Type := 0;
      Entries : Route_Array      := [others => Empty_Route];
   end record;

   function Coordinates_Are_Unique (History : Routing_History) return Boolean is
     (for all I in 1 .. History.Count =>
        (for all J in I + 1 .. History.Count =>
           not (Equal_Token
                  (History.Entries (I).Scheduled.Token,
                   History.Entries (J).Scheduled.Token)
                and then Equal_Token
                  (History.Entries (I).Locus.Token,
                   History.Entries (J).Locus.Token)
                and then Equal_Date
                  (History.Entries (I).Effective_On,
                   History.Entries (J).Effective_On))));

   type Route_State is (Route_Unknown, Route_Unmanaged, Route_Managed);
   type Route_Result is record
      State       : Route_State := Route_Unknown;
      Purpose     : Token_Text;
      Effective_On: Date_Type   := (Year => 2026, Month => 1, Day => 1);
   end record;

   --  Latest assertion visible at As_Of. Row order carries no authority.
   procedure Find_Current_Route
     (History   : Routing_History;
      Scheduled : Scheduled_Id;
      Locus     : Locus_Id;
      As_Of     : Date_Type;
      Result    : out Route_Result);

end HRA_N.Core.Scheduled_Routing;
