-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Creation_Writer
--
--  Independent canonical Scheduled-creation publisher.
--
--  This package writes the same LOAM-SCHEDULED-LIFECYCLE v1 authority consumed
--  by Loam.  HRA-N keeps its own bounded admission and correspondence checks;
--  those working-set limits are not Loam lifetime laws.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Scheduled_Creation_Writer is

   type Creation_Draft is record
      Expected_Day : Date_Type;
      Measure      : Measure_Id;
      Changes      : Change_List;
   end record;

   type Publish_Result is record
      Success      : Boolean := False;
      Scheduled_Id : HRA_N.Core.Scheduled.Scheduled_Id;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Publish one fresh Scheduled occurrence into Root_Path/scheduled.loam.
   --
   --  Ownership order intentionally matches Loam:
   --    Scheduled lifecycle authority -> actual.loam
   --
   --  Current Actual and Locus admission are re-read under that ownership.
   --  Candidate bytes and staged bytes must both re-admit and correspond to
   --  exactly one fresh occurrence before the authority switch.
   function Publish_Creation
     (Root_Path : String;
      Draft     : Creation_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Creation_Writer;
