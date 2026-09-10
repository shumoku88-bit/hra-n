-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Scheduled_Publisher
--
--  Terminal completion publisher for scheduled obligations.
--  Safely coordinates Scheduled lifecycle authority and Movement manifest authority
--  under strict two-phase locking order:
--    Scheduled lifecycle lock -> Movement manifest lock
-------------------------------------------------------------------------------

with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Application.Scheduled_Publisher is

   type Scheduled_Publish_Result is record
      Success      : Boolean             := False;
      Event_Id_Str : String (1 .. 64)    := [others => ' '];
      Event_Id_Len : Natural             := 0;
      Error_Reason : String (1 .. 128)   := [others => ' '];
      Error_Len    : Natural             := 0;
   end record;

   type Scheduled_Mutation_Result is record
      Success      : Boolean             := False;
      Target_Str   : String (1 .. 64)    := [others => ' '];
      Target_Len   : Natural             := 0;
      Error_Reason : String (1 .. 128)   := [others => ' '];
      Error_Len    : Natural             := 0;
   end record;

   --  Complete an open scheduled movement by publishing an actual movement
   --  receipt into movement authority and registering the completion in scheduled lifecycle.
   function Complete_Scheduled_Movement
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Target_Id      : Scheduled_Id;
      Valid_On       : Date_Type;
      Description    : String := "") return Scheduled_Publish_Result;

   --  Add a new scheduled obligation after validating admitted vocabulary
   function Add_Scheduled_Obligation
     (Scheduled_Path : String;
      Authority_Dir  : String;
      From_Locus     : String;
      To_Locus       : String;
      Amount         : Quanta_Type;
      Valid_On       : Date_Type;
      Measure_Str    : String := "jpy") return Scheduled_Mutation_Result;

   --  Retire (cancel) an open scheduled obligation
   function Retire_Scheduled_Obligation
     (Scheduled_Path : String;
      Target_Id      : Scheduled_Id) return Scheduled_Mutation_Result;

end HRA_N.Application.Scheduled_Publisher;
