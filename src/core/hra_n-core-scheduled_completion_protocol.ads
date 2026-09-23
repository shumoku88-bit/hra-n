-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Scheduled_Completion_Protocol
--
--  Proof-facing composition of Loam's relation-first Scheduled completion.
--
--  The protocol has three semantic states:
--
--    before -> inert middle -> effective finish
--
--  Both underlying transitions are preflighted before the middle state is
--  admitted.  The middle retains the Scheduled -> Actual claim while the Actual
--  endpoint is still absent.  The finish preserves that claim and selects the
--  exact complete Actual Event.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Writer_Transition;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Completion_Transition;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Scheduled_Completion_Protocol with
  SPARK_Mode => On
is
   pragma Pure;

   type Protocol_Status is
     (Protocol_Composed,
      Endpoint_Mismatch,
      Scheduled_Preflight_Rejected,
      Actual_Preflight_Rejected);

   function Endpoint_Matches
     (Claim : Completion_Record;
      Added : HRA_N.Core.Event.Event) return Boolean is
     (Equal_Token
        (Claim.Actual.Token,
         HRA_N.Core.Event.Id (Added).Token));

   function Claim_Is_Last
     (Image : Scheduled_Lifecycle;
      Claim : Completion_Record) return Boolean is
     (Image.Comp_Count > 0
      and then Image.Comp_Items (Image.Comp_Count) = Claim);

   function Actual_Endpoint_Absent
     (Image : Semantic_Image;
      Claim : Completion_Record) return Boolean is
     (Reference_Lookup (Image, Claim.Actual).State = Not_Found);

   function Inert_Middle
     (Scheduled : Scheduled_Lifecycle;
      Actual    : Semantic_Image;
      Claim     : Completion_Record) return Boolean is
     (Claim_Is_Last (Scheduled, Claim)
      and then Actual_Endpoint_Absent (Actual, Claim));

   function Effective_Finish
     (Scheduled : Scheduled_Lifecycle;
      Actual    : Semantic_Image;
      Claim     : Completion_Record;
      Added     : HRA_N.Core.Event.Event) return Boolean is
     (Claim_Is_Last (Scheduled, Claim)
      and then Reference_Lookup (Actual, Claim.Actual).State = Found
      and then Reference_Lookup (Actual, Claim.Actual).Value = Added);

   function Relation_First_Completion
     (Scheduled_Before : Scheduled_Lifecycle;
      Actual_Before    : Semantic_Image;
      Claim            : Completion_Record;
      Added_Actual     : HRA_N.Core.Event.Event;
      Target_Snapshot  : Snapshot_Id;
      Scheduled_Middle : Scheduled_Lifecycle;
      Actual_Middle    : Semantic_Image;
      Scheduled_After  : Scheduled_Lifecycle;
      Actual_After     : Semantic_Image) return Boolean is
     (Endpoint_Matches (Claim, Added_Actual)
      and then
        HRA_N.Core.Scheduled_Completion_Transition.One_Fresh_Completion
          (Scheduled_Before, Claim, Scheduled_Middle)
      and then Actual_Middle = Actual_Before
      and then Inert_Middle
        (Scheduled_Middle, Actual_Middle, Claim)
      and then Scheduled_After = Scheduled_Middle
      and then
        HRA_N.Core.Actual_Writer_Transition.One_Fresh_Append
          (Actual_Before,
           Added_Actual,
           Target_Snapshot,
           Actual_After)
      and then Effective_Finish
        (Scheduled_After, Actual_After, Claim, Added_Actual));

   --  Preflight both semantic transitions first.  Only after both can succeed
   --  do the outputs expose the relation-first middle and effective finish.
   procedure Compose_Relation_First
     (Scheduled_Before : Scheduled_Lifecycle;
      Actual_Before    : Semantic_Image;
      Claim            : Completion_Record;
      Added_Actual     : HRA_N.Core.Event.Event;
      Target_Snapshot  : Snapshot_Id;
      Scheduled_Middle : out Scheduled_Lifecycle;
      Actual_Middle    : out Semantic_Image;
      Scheduled_After  : out Scheduled_Lifecycle;
      Actual_After     : out Semantic_Image;
      Status           : out Protocol_Status)
   with
     Post =>
       (if Status = Protocol_Composed then
           Relation_First_Completion
             (Scheduled_Before,
              Actual_Before,
              Claim,
              Added_Actual,
              Target_Snapshot,
              Scheduled_Middle,
              Actual_Middle,
              Scheduled_After,
              Actual_After));

end HRA_N.Core.Scheduled_Completion_Protocol;
