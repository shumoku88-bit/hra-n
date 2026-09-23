-------------------------------------------------------------------------------
--  HRA-N: shared effective Scheduled lifecycle interpretation
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Actual_Reader;

package HRA_N.Application.Scheduled_Effective_State is

   type Completion_State is
     (No_Retained_Completion,
      Effective_Completion,
      Unresolved_Completion);

   type Completion_Observation is record
      State  : Completion_State := No_Retained_Completion;
      Actual : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   --  Structural lifecycle admission corresponding to Loam's shared
   --  currentOpenScheduled preconditions.  A retained completion does not
   --  require its Actual endpoint to exist: that absence is interpreted
   --  separately as an unresolved/inert completion claim.
   function Lifecycle_Readable
     (Lifecycle : Scheduled_Lifecycle) return Boolean;

   --  Observe one retained completion against current canonical Actual
   --  evidence.  Missing Actual keeps the Scheduled occurrence current-open.
   function Observe_Completion
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id;
      Actual    : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result)
      return Completion_Observation;

end HRA_N.Application.Scheduled_Effective_State;
