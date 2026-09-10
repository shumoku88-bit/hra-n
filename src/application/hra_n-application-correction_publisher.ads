-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Correction_Publisher
--
--  Resumable Event correction publisher.
--  Adheres strictly to the normative authority protocol:
--    1. CURRENT writer ownership
--    2. Re-reads Movement, Correction, and Reversal authorities under lock
--    3. Requires target to be current correction frontier tip
--    4. Rejects relation-involved targets
--    5. Rejects reversal-involved targets
--    6. Constructs replacement Event from balanced nonzero JPY effects
--    7. Carries target occurrence date to replacement
--    8. Publishes description only if explicitly provided
--    9. Persists Correction sidecar first
--   10. Activates replacement Event in CURRENT last
--   11. Resumes with same correction-N and replacement-N on retry
--   12. Sibling pending corrections fail closed without choosing a winner
--   13. Admits complete candidate correction frontier
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Types;       use HRA_N.Core.Types;
with HRA_N.Core.Event;       use HRA_N.Core.Event;
with HRA_N.Core.Correction;  use HRA_N.Core.Correction;

package HRA_N.Application.Correction_Publisher is

   type Correction_Draft is record
      Target      : Event_Id;
      Effects     : Effect_List;
      Description : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Convenience helper for two-legged Movement corrections.
   function Make_Two_Party_Draft
     (Target      : String;
      From_Locus  : String;
      To_Locus    : String;
      Amount      : Quanta_Type;
      Description : String := "") return Correction_Draft;

   type Correction_Receipt is record
      Success               : Boolean           := False;
      Target                : Event_Id          := (Token => (Length => 0, Value => [others => ' ']));
      Replacement           : Event_Id          := (Token => (Length => 0, Value => [others => ' ']));
      Correction            : Correction_Id     := (Token => (Length => 0, Value => [others => ' ']));
      Carried_Date          : Boolean           := False;
      Published_Description : Boolean           := False;
      Resumed               : Boolean           := False;
      Error_Reason          : String (1 .. 256) := [others => ' '];
      Error_Len             : Natural           := 0;
   end record;

   --  Deterministic fault injection point for testing sidecar-first crash & resume.
   type Correction_Fault is
     (Correction_Fault_None,
      Correction_Fault_Interrupt_After_Sidecar);

   function Publish_Correction
     (Authority_Dir   : String;
      Correction_Path : String;
      Reversals_Path  : String;
      Draft           : Correction_Draft;
      Fault           : Correction_Fault := Correction_Fault_None) return Correction_Receipt;

end HRA_N.Application.Correction_Publisher;
