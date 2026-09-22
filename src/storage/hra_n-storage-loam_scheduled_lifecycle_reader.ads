-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader
--
--  Independent read-only bridge for LOAM-SCHEDULED-LIFECYCLE v1.
--
--  This reader exists first as guard evidence for canonical Actual operations
--  that must prove independence from Scheduled-completion provenance.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;

package HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader is

   type Read_Result is record
      Success      : Boolean := False;
      Lifecycle    : Scheduled_Lifecycle;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Decode one exact canonical lifecycle byte image.  HRA-N currently admits
   --  at most 128 Scheduled occurrences/terminal rows and 8 changes per
   --  occurrence.  Those are working-set bounds, not Loam lifetime laws.
   function Read_Content (Content : String) return Read_Result;

   function Read_File (Path : String) return Read_Result;

   --  True when retained Scheduled-completion evidence names Actual_Id.
   function Completion_Mentions_Actual
     (Result    : Read_Result;
      Actual_Id : Event_Id) return Boolean;

end HRA_N.Storage.Loam_Scheduled_Lifecycle_Reader;
