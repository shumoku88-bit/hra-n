-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Writer
--
--  Atomic writer for Scheduled lifecycle authority mutations.
--  Appends terminal completion and retirement facts under writer ownership
--  via staging, fsync, and atomic rename.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
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

   --  Append a new scheduled obligation record to a Scheduled lifecycle authority file.
   function Append_Scheduled
     (Scheduled_Path : String;
      Target         : Scheduled_Id;
      Valid_On       : Date_Type;
      From_Locus     : String;
      To_Locus       : String;
      Amount         : Quanta_Type;
      Measure        : Measure_Id) return Write_Scheduled_Result;

   --  Append a retirement (cancellation) fact to a Scheduled lifecycle authority file.
   function Append_Retirement
     (Scheduled_Path : String;
      Target         : Scheduled_Id) return Write_Scheduled_Result;

   --  Append a replacement fact to a Scheduled lifecycle authority file.
   function Append_Replacement
     (Scheduled_Path : String;
      Source         : Scheduled_Id;
      Replacement    : Scheduled_Id) return Write_Scheduled_Result;

   --  Serialize complete Scheduled_Lifecycle to canonical format string.
   function Format_Scheduled_Lifecycle
     (Lifecycle : Scheduled_Lifecycle) return String;

   --  Atomically write complete Scheduled_Lifecycle to file.
   function Write_Scheduled_Lifecycle
     (Scheduled_Path : String;
      Lifecycle      : Scheduled_Lifecycle) return Write_Scheduled_Result;

end HRA_N.Storage.Scheduled_Writer;
