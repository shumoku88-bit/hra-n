-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Scheduled_Inspection
--
--  Replacement-aware current-open Scheduled inspection and balance effects.
--  Encodes Loam's 4-phase lifecycle ontology and open-world projection:
--    - Day evidence (Due vs Unknown)
--    - Scheduled balance effects before end-exclusive boundary
--    - Scheduled suppression comparison (baseline vs projected)
-------------------------------------------------------------------------------

with HRA_N.Core.Types;                      use HRA_N.Core.Types;
with HRA_N.Core.Validity;                   use HRA_N.Core.Validity;
with HRA_N.Core.Coverage;                   use HRA_N.Core.Coverage;
with HRA_N.Core.Scheduled;                  use HRA_N.Core.Scheduled;
with HRA_N.Storage.Event_Reader;            use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Balance_View_Reader;     use HRA_N.Storage.Balance_View_Reader;

package HRA_N.Application.Scheduled_Inspection is

   type Inspection_Status is
     (Status_Ok,
      Status_Unknown_Completion_Scheduled,
      Status_Unknown_Retirement_Scheduled,
      Status_Unknown_Replacement_Scheduled,
      Status_Invalid_Replacement_Graph,
      Status_Conflicting_Terminal_Evidence,
      Status_Target_Not_Open);

   type Open_Occurrences_Result is record
      Status      : Inspection_Status  := Status_Ok;
      Occurrences : Occurrence_Array   := [others =>
        (Id           => (Token => (0, [others => ' '])),
         Expected_Day => (2026, 1, 1),
         Measure      => (Token => (0, [others => ' '])),
         Changes      => (0, others => <>))];
      Count       : Natural            := 0;
   end record;

   --  Project the complete current-open Scheduled set with replacement awareness.
   --  Fails closed with typed status on structural lifecycle/replacement inconsistencies.
   function Current_Open_Scheduled
     (Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector) return Open_Occurrences_Result;

   ----------------------------------------------------------------------------
   --  Day Evidence (Open-world: Due vs Unknown)
   ----------------------------------------------------------------------------

   type Day_Evidence_Kind is
     (Evidence_Due,
      Evidence_Unknown,
      Evidence_Refused);

   type Day_Evidence_Result is record
      Kind        : Day_Evidence_Kind  := Evidence_Unknown;
      Status      : Inspection_Status  := Status_Ok;
      Occurrences : Occurrence_Array   := [others =>
        (Id           => (Token => (0, [others => ' '])),
         Expected_Day => (2026, 1, 1),
         Measure      => (Token => (0, [others => ' '])),
         Changes      => (0, others => <>))];
      Count       : Natural            := 0;
   end record;

   --  Query one exact day without inventing closed-world Scheduled semantics.
   --  Due if explicit current-open evidence exists on that day; Unknown otherwise.
   function Query_Day_Evidence
     (Lifecycle : Scheduled_Lifecycle;
      Events    : Event_Vectors.Vector;
      Day       : Date_Type) return Day_Evidence_Result;

   ----------------------------------------------------------------------------
   --  Scheduled Balance Effects
   ----------------------------------------------------------------------------

   type Scheduled_Balance_Effect is record
      Coordinate : Coordinate_Type;
      Quantity   : Quanta_Type := 0;
   end record;

   type Balance_Effect_Array is array (1 .. Max_Balance_Coordinates) of Scheduled_Balance_Effect;

   type Balance_Effects_List is record
      Count   : Natural              := 0;
      Effects : Balance_Effect_Array := [others =>
        (Coordinate => Empty_Coordinate, Quantity => 0)];
   end record;

   type Balance_Effects_Result is record
      Status  : Inspection_Status   := Status_Ok;
      Effects : Balance_Effects_List;
   end record;

   --  Project replacement-aware current-open Scheduled effects through selected
   --  balance coordinates strictly before End_Exclusive.
   function Calculate_Balance_Effects
     (Lifecycle     : Scheduled_Lifecycle;
      Events        : Event_Vectors.Vector;
      Coordinates   : Balance_Coordinate_List;
      End_Exclusive : Date_Type) return Balance_Effects_Result;

   ----------------------------------------------------------------------------
   --  Scheduled Suppression Comparison
   ----------------------------------------------------------------------------

   type Suppression_Comparison_Result is record
      Status    : Inspection_Status   := Status_Ok;
      Baseline  : Balance_Effects_List;
      Projected : Balance_Effects_List;
   end record;

   --  Compare baseline Scheduled balance effects with a hypothetical read-only
   --  projection suppressing exactly one currently open Scheduled identity.
   function Compare_Suppression
     (Lifecycle     : Scheduled_Lifecycle;
      Events        : Event_Vectors.Vector;
      Coordinates   : Balance_Coordinate_List;
      End_Exclusive : Date_Type;
      Target_Id     : Scheduled_Id) return Suppression_Comparison_Result;

end HRA_N.Application.Scheduled_Inspection;
