-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Budget_Window
--
--  Coordinate-window Budget and Envelope Projection Engine.
--  Implements Lean Observation 181:
--    Entitlement = independent component observation (from Capacity)
--    Consumption = independent component observation (from Actual Routing & Validity)
--    Remaining   = derived observation (Entitlement - Consumption)
--  No Period or Remaining state is stored.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;          use HRA_N.Core.Types;
with HRA_N.Core.Capacity;       use HRA_N.Core.Capacity;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Validity;       use HRA_N.Core.Validity;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;

package HRA_N.Application.Budget_Window is

   Max_Window_Purposes : constant := 32;

   type Envelope_Row is record
      Purpose     : Token_Text;
      Entitlement : Quanta_Type;
      Consumption : Quanta_Type;
      Remaining   : Quanta_Type;
   end record;

   Empty_Envelope_Row : constant Envelope_Row :=
     (Purpose     => (Length => 0, Value => [others => ' ']),
      Entitlement => Zero_Quanta,
      Consumption => Zero_Quanta,
      Remaining   => Zero_Quanta);

   subtype Purpose_Count_Type is Natural range 0 .. Max_Window_Purposes;
   subtype Purpose_Index_Type is Positive range 1 .. Max_Window_Purposes;
   type Envelope_Row_Array is array (Purpose_Index_Type) of Envelope_Row;

   type Budget_Window_Report is record
      Start_Year          : Natural;
      Start_Month         : Natural;
      Start_Day           : Natural;
      End_Year            : Natural;
      End_Month           : Natural;
      End_Day             : Natural;

      Row_Count           : Purpose_Count_Type := 0;
      Rows                : Envelope_Row_Array := [others => Empty_Envelope_Row];

      Unallocated_Funds   : Quanta_Type        := Zero_Quanta;
      Total_Entitlement   : Quanta_Type        := Zero_Quanta;
      Total_Consumption   : Quanta_Type        := Zero_Quanta;
      Total_Remaining     : Quanta_Type        := Zero_Quanta;

      Capacity_Sum        : Long_Long_Integer  := 0;
      Movements_Count     : Natural            := 0;
      Events_Considered   : Natural            := 0;
   end record;

   function Universal_Capacity_Holds (Rep : Budget_Window_Report) return Boolean is
     (Rep.Capacity_Sum = 0);

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
      Report       : out Budget_Window_Report);

end HRA_N.Application.Budget_Window;
