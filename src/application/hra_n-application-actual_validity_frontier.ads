-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Actual_Validity_Frontier
--
--  Admissibility and current-frontier projection for ActualValidity history.
--  Adheres strictly to the normative validity history laws:
--    1. Retains all historical occurrence-date facts.
--    2. Superseded date facts leave the current frontier.
--    3. Preserves same-Event invariant across corrections.
--    4. Sibling date corrections fail closed without choosing a winner.
--    5. Cross-event corrections fail closed.
--    6. Acyclic correction chains.
--    7. Exactly at most one current date per Event.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Actual_Validity_Frontier is

   function Frontier_Admissible (History : Validity_History) return Boolean;

   function Project_Memory
     (History : Validity_History;
      Memory  : out Validity_Memory) return Boolean;

   procedure Find_Current_Fact
     (History : in  Validity_History;
      Target  : in  Event_Id;
      Fact    : out Validity_Fact;
      Found   : out Boolean);

   function Fresh_Fact_Id (History : Validity_History) return Validity_Fact_Id;

   function Fresh_Correction_Id (History : Validity_History) return Validity_Correction_Id;

end HRA_N.Application.Actual_Validity_Frontier;
