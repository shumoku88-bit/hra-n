with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Correction; use HRA_N.Core.Correction;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;

package HRA_N.Application.Correction_Frontier is
   type Resolution_State is (Resolution_Absent, Resolution_Unresolved, Resolution_Current);
   type Resolution_Result is record
      State : Resolution_State := Resolution_Absent;
      Effective : Event_Id := (Token => (Length => 0, Value => [others => ' ']));
      Depth : Natural := 0;
   end record;
   function Frontier_Admissible
     (Events : Event_Vectors.Vector; Corrections : Correction_Memory) return Boolean;
   procedure Resolve
     (Events : Event_Vectors.Vector; Corrections : Correction_Memory;
      Original : Event_Id; Result : out Resolution_Result);
end HRA_N.Application.Correction_Frontier;
