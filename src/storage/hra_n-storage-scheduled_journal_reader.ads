-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Journal_Reader
--
--  Unified parser for canonical scheduled.hra files.
--  Constructs complete Scheduled_Lifecycle (occurrences, completions,
--  retirements, replacements) in a single fail-closed traversal.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Storage.Scheduled_Journal_Reader is

   type Scheduled_Journal_Result is record
      Success      : Boolean := False;
      Lifecycle    : Scheduled_Lifecycle;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Scheduled_Journal_File (Path : String) return Scheduled_Journal_Result;

end HRA_N.Storage.Scheduled_Journal_Reader;
