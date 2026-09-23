-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Scheduled_Completion_Transition
--
--  Bounded proof-facing semantics for one canonical Scheduled completion claim.
--
--  This transition models only the Scheduled authority step.  Canonical Loam
--  publishes the Scheduled -> Actual claim before the Actual Event so an
--  interrupted completion is retained but inert until the Actual endpoint is
--  selected.  Actual append semantics and filesystem publication are separate
--  qualification boundaries.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;

package HRA_N.Core.Scheduled_Completion_Transition with
  SPARK_Mode => On
is
   pragma Pure;

   type Completion_Transition_Status is
     (Completion_Transitioned,
      Source_Completions_Invalid,
      Source_Completion_Full,
      Unknown_Scheduled_Id,
      Scheduled_Not_Current_Open,
      Actual_Endpoint_Already_Claimed);

   --  Completion is one-to-one on both Scheduled source and Actual endpoint.
   --  This is the proof-facing form of Loam's endpoint ownership law.
   function Completion_Pairs_Are_One_To_One
     (Image : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Image.Comp_Count =>
        (for all J in I + 1 .. Image.Comp_Count =>
           not Equal_Token
             (Image.Comp_Items (I).Scheduled.Token,
              Image.Comp_Items (J).Scheduled.Token)
           and then
           not Equal_Token
             (Image.Comp_Items (I).Actual.Token,
              Image.Comp_Items (J).Actual.Token)));

   function Completion_Source_Fresh
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (for all I in 1 .. Image.Comp_Count =>
        not Equal_Token
          (Image.Comp_Items (I).Scheduled.Token, Target.Token));

   function Actual_Endpoint_Fresh
     (Image  : Scheduled_Lifecycle;
      Actual : Event_Id) return Boolean is
     (for all I in 1 .. Image.Comp_Count =>
        not Equal_Token
          (Image.Comp_Items (I).Actual.Token, Actual.Token));

   --  A completion may be added only when no terminal evidence already owns
   --  the Scheduled source.  This is stated directly for proof rather than
   --  deriving it from a closed/open status field.
   function No_Terminal_For
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (Completion_Source_Fresh (Image, Target)
      and then
        (for all I in 1 .. Image.Ret_Count =>
           not Equal_Token
             (Image.Ret_Items (I).Scheduled.Token, Target.Token))
      and then
        (for all I in 1 .. Image.Repl_Count =>
           not Equal_Token
             (Image.Repl_Items (I).Original.Token, Target.Token)));

   function Occurrence_Evidence_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (Target.Sched_Count = Source.Sched_Count
      and then
        (for all I in 1 .. Source.Sched_Count =>
           Target.Sched_Items (I) = Source.Sched_Items (I)));

   function Completion_Prefix_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Source.Comp_Count =>
        Target.Comp_Items (I) = Source.Comp_Items (I));

   function Other_Terminal_Evidence_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (Target.Ret_Count = Source.Ret_Count
      and then Target.Repl_Count = Source.Repl_Count
      and then
        (for all I in 1 .. Source.Ret_Count =>
           Target.Ret_Items (I) = Source.Ret_Items (I))
      and then
        (for all I in 1 .. Source.Repl_Count =>
           Target.Repl_Items (I) = Source.Repl_Items (I)));

   function One_Fresh_Completion
     (Source : Scheduled_Lifecycle;
      Added  : Completion_Record;
      Target : Scheduled_Lifecycle) return Boolean is
     (Completion_Pairs_Are_One_To_One (Source)
      and then Source.Comp_Count < Max_Scheduled_Entries
      and then Sched_Exists (Source, Added.Scheduled)
      and then No_Terminal_For (Source, Added.Scheduled)
      and then Actual_Endpoint_Fresh (Source, Added.Actual)
      and then Occurrence_Evidence_Preserved (Source, Target)
      and then Target.Comp_Count = Source.Comp_Count + 1
      and then Completion_Prefix_Preserved (Source, Target)
      and then Target.Comp_Items (Target.Comp_Count) = Added
      and then Other_Terminal_Evidence_Preserved (Source, Target)
      and then Completion_Pairs_Are_One_To_One (Target));

   procedure Append_Fresh_Completion
     (Source : Scheduled_Lifecycle;
      Added  : Completion_Record;
      Target : out Scheduled_Lifecycle;
      Status : out Completion_Transition_Status)
   with
     Post =>
       (if not Completion_Pairs_Are_One_To_One (Source) then
           Status = Source_Completions_Invalid
        elsif Source.Comp_Count = Max_Scheduled_Entries then
           Status = Source_Completion_Full
        elsif not Sched_Exists (Source, Added.Scheduled) then
           Status = Unknown_Scheduled_Id
        elsif not No_Terminal_For (Source, Added.Scheduled) then
           Status = Scheduled_Not_Current_Open
        elsif not Actual_Endpoint_Fresh (Source, Added.Actual) then
           Status = Actual_Endpoint_Already_Claimed
        else
           Status = Completion_Transitioned
           and then One_Fresh_Completion (Source, Added, Target));

end HRA_N.Core.Scheduled_Completion_Transition;
