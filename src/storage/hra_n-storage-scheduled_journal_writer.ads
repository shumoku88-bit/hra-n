-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Journal_Writer
--
--  Atomic writers for canonical scheduled.hra files.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Storage.Scheduled_Journal_Writer is

   type Write_Result is record
      Success      : Boolean := False;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Atomically rewrite scheduled.hra from a Scheduled_Lifecycle structure
   function Write_Scheduled_Journal_File
     (Path      : String;
      Lifecycle : Scheduled_Lifecycle) return Write_Result;

end HRA_N.Storage.Scheduled_Journal_Writer;
