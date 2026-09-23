-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Replacement_Writer
--
--  Independent canonical Scheduled-replacement publisher.
--
--  One publication appends both the fresh successor occurrence and the
--  source -> successor replacement relation to scheduled.loam.  HRA-N refuses
--  any retained completion claim on the source rather than creating
--  cross-kind terminal conflict.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Scheduled_Replacement_Writer is

   type Replacement_Draft is record
      Source       : Scheduled_Id;
      Expected_Day : Date_Type;
      Measure      : Measure_Id;
      Changes      : Change_List;
   end record;

   type Publish_Result is record
      Success        : Boolean := False;
      Replacement_Id : Scheduled_Id;
      Error_Reason   : String (1 .. 192) := [others => ' '];
      Error_Len      : Natural := 0;
   end record;

   --  Publish one replacement as a single canonical lifecycle image switch:
   --
   --    retained source
   --         |
   --         +--> fresh Scheduled occurrence
   --         +--> source -> fresh occurrence replacement relation
   --
   --  Ownership order intentionally matches Loam:
   --    Scheduled lifecycle authority -> actual.loam
   function Publish_Replacement
     (Root_Path : String;
      Draft     : Replacement_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Replacement_Writer;
