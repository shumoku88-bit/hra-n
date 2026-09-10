-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Writer
--
--  Atomic writer for Scheduled lifecycle authority mutations.
--  Appends terminal completion and retirement facts under writer ownership
--  via staging, fsync, and atomic rename.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Storage.Scheduled_Writer is

   type Write_Scheduled_Result is record
      Success      : Boolean             := False;
      Error_Reason : String (1 .. 128)   := [others => ' '];
      Error_Len    : Natural             := 0;
   end record;

   --  Append a completion terminal fact to a Scheduled lifecycle authority file.
   function Append_Completion
     (Scheduled_Path : String;
      Target         : Scheduled_Id;
      Actual_Event   : Event_Id) return Write_Scheduled_Result;

end HRA_N.Storage.Scheduled_Writer;
