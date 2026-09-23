-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Scheduled_Completion_Protocol
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Writer_Transition;
use HRA_N.Core.Actual_Writer_Transition;
with HRA_N.Core.Scheduled_Completion_Transition;
use HRA_N.Core.Scheduled_Completion_Transition;

package body HRA_N.Core.Scheduled_Completion_Protocol with
  SPARK_Mode => On
is

   procedure Prove_Fresh_Endpoint_Absent
     (Source : Semantic_Image;
      Added  : HRA_N.Core.Event.Event)
   with
     Ghost,
     Pre => HRA_N.Core.Actual_Writer_Transition.Fresh_For (Source, Added),
     Post =>
       Reference_Lookup
         (Source, HRA_N.Core.Event.Id (Added)).State = Not_Found;

   procedure Prove_Fresh_Endpoint_Absent
     (Source : Semantic_Image;
      Added  : HRA_N.Core.Event.Event)
   is
      Result : constant Lookup_Result :=
        Reference_Lookup (Source, HRA_N.Core.Event.Id (Added));
   begin
      pragma Assert (Result.State /= Invalid_Index);
      if Result.State = Found then
         pragma Assert (Result.Position <= Source.Count);
         pragma Assert (Result.Value = Source.Events (Result.Position));
         pragma Assert
           (Same_Id
              (HRA_N.Core.Event.Id (Result.Value),
               HRA_N.Core.Event.Id (Added)));
         pragma Assert
           (Same_Id
              (HRA_N.Core.Event.Id
                 (Source.Events (Result.Position)),
               HRA_N.Core.Event.Id (Added)));
         pragma Assert (False);
      end if;
      pragma Assert (Result.State = Not_Found);
   end Prove_Fresh_Endpoint_Absent;

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
   is
      Scheduled_Candidate : Scheduled_Lifecycle;
      Scheduled_Status    : Completion_Transition_Status;
      Actual_Candidate    : Semantic_Image;
      Actual_Status       : Transition_Status;
   begin
      Scheduled_Middle := Scheduled_Before;
      Actual_Middle := Actual_Before;
      Scheduled_After := Scheduled_Before;
      Actual_After := Actual_Before;

      if not Endpoint_Matches (Claim, Added_Actual) then
         Status := Endpoint_Mismatch;
         return;
      end if;

      --  Semantic preflight of the Scheduled relation.  No output state is
      --  advanced yet.
      Append_Fresh_Completion
        (Scheduled_Before,
         Claim,
         Scheduled_Candidate,
         Scheduled_Status);

      if Scheduled_Status /= Completion_Transitioned then
         Status := Scheduled_Preflight_Rejected;
         return;
      end if;

      --  Semantic preflight of the Actual append before exposing the middle.
      --  This mirrors Loam's rule that an impossible Actual completion must not
      --  leave a newly published terminal claim behind.
      Append_Fresh
        (Actual_Before,
         Added_Actual,
         Target_Snapshot,
         Actual_Candidate,
         Actual_Status);

      if Actual_Status /= Transitioned then
         Status := Actual_Preflight_Rejected;
         return;
      end if;

      pragma Assert
        (One_Fresh_Completion
           (Scheduled_Before,
            Claim,
            Scheduled_Candidate));
      pragma Assert
        (One_Fresh_Append
           (Actual_Before,
            Added_Actual,
            Target_Snapshot,
            Actual_Candidate));
      pragma Assert
        (HRA_N.Core.Actual_Writer_Transition.Fresh_For
           (Actual_Before, Added_Actual));

      Prove_Fresh_Endpoint_Absent (Actual_Before, Added_Actual);

      Scheduled_Middle := Scheduled_Candidate;
      Actual_Middle := Actual_Before;
      Scheduled_After := Scheduled_Candidate;
      Actual_After := Actual_Candidate;

      pragma Assert
        (Claim_Is_Last (Scheduled_Middle, Claim));
      pragma Assert
        (Equal_Token
           (Claim.Actual.Token,
            HRA_N.Core.Event.Id (Added_Actual).Token));
      pragma Assert
        (Reference_Lookup
           (Actual_Middle,
            HRA_N.Core.Event.Id (Added_Actual)).State = Not_Found);
      pragma Assert
        (Reference_Lookup
           (Actual_Middle,
            Claim.Actual).State = Not_Found);
      pragma Assert
        (Inert_Middle
           (Scheduled_Middle, Actual_Middle, Claim));

      Prove_Added_Lookup
        (Actual_Before,
         Added_Actual,
         Target_Snapshot,
         Actual_After);

      pragma Assert
        (Reference_Lookup
           (Actual_After,
            HRA_N.Core.Event.Id (Added_Actual)).State = Found);
      pragma Assert
        (Reference_Lookup
           (Actual_After,
            HRA_N.Core.Event.Id (Added_Actual)).Value = Added_Actual);
      pragma Assert
        (Reference_Lookup
           (Actual_After,
            Claim.Actual).State = Found);
      pragma Assert
        (Reference_Lookup
           (Actual_After,
            Claim.Actual).Value = Added_Actual);
      pragma Assert
        (Effective_Finish
           (Scheduled_After, Actual_After, Claim, Added_Actual));

      Status := Protocol_Composed;
   end Compose_Relation_First;

end HRA_N.Core.Scheduled_Completion_Protocol;
