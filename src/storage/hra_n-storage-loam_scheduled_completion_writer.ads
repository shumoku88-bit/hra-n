-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Completion_Writer
--
--  Canonical Scheduled completion-claim publisher.
--
--  This package publishes only the first half of Loam's relation-first
--  completion protocol: the Scheduled -> Actual terminal claim.  The Actual
--  Event is deliberately not created here.  If publication is interrupted
--  after this step, the retained claim remains inert until the deterministic
--  Actual endpoint exists, and a retry may reuse that exact claim.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;

package HRA_N.Storage.Loam_Scheduled_Completion_Writer is

   type Completion_Claim_State is
     (Claim_Not_Ready,
      Claim_Published_Fresh,
      Claim_Already_Inert);

   type Publish_Result is record
      State        : Completion_Claim_State := Claim_Not_Ready;
      Actual_Id    : Event_Id;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Publish or recover the canonical completion claim for one retained
   --  Scheduled identity.
   --
   --  The Actual endpoint is deterministic:
   --    scheduled-completion:<ScheduledId>
   --
   --  Ownership order matches Loam:
   --    Scheduled lifecycle authority -> actual.loam
   --
   --  Fresh publication changes scheduled.loam only.  If the exact claim is
   --  already retained while its Actual endpoint is still absent, the result
   --  is Claim_Already_Inert and no bytes are rewritten.
   function Publish_Completion_Claim
     (Root_Path : String;
      Scheduled : Scheduled_Id) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Completion_Writer;
