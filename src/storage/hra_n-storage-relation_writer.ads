-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Relation_Writer
-------------------------------------------------------------------------------

with HRA_N.Core.Relation; use HRA_N.Core.Relation;

package HRA_N.Storage.Relation_Writer is

   function Encode_Relation_Units (Memory : Unit_Memory) return String;

   function Encode_Relation_Discharges
     (Memory : Discharge_Memory) return String;

end HRA_N.Storage.Relation_Writer;
