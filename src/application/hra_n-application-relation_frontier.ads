-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Relation_Frontier
--
--  Source-local admission and exact outstanding projection for one retained
--  RelationUnit. Unresolved evidence is explicit and never consumed as zero.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;           use HRA_N.Core.Types;
with HRA_N.Core.Relation;        use HRA_N.Core.Relation;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;

package HRA_N.Application.Relation_Frontier is

   type Outstanding_State is
     (Target_Absent,
      Evidence_Unresolved,
      Relation_Open,
      Relation_Discharged);

   type Outstanding_Result is record
      State                    : Outstanding_State := Target_Absent;
      Original_Quantity        : Quanta_Type       := Zero_Quanta;
      Discharged_Quantity      : Quanta_Type       := Zero_Quanta;
      Outstanding_Quantity     : Quanta_Type       := Zero_Quanta;
      Admitted_Discharge_Count : Natural           := 0;
      Measure                  : Measure_Id         :=
        (Token => (Length => 0, Value => [others => ' ']));
   end record;

   --  Derive one current relation balance. Outstanding is projection state,
   --  never retained independently from Unit and Discharge provenance.
   procedure Project_Outstanding
     (Events     : Event_Vectors.Vector;
      Units      : Unit_Memory;
      Discharges : Discharge_Memory;
      Target_Id  : Token_Text;
      Result     : out Outstanding_Result);

end HRA_N.Application.Relation_Frontier;
