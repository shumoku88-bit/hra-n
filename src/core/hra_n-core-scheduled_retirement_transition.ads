-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Scheduled_Retirement_Transition
--
--  Bounded proof-facing semantics for one canonical Scheduled retirement.
--
--  A retained completion claim is rejected explicitly before ordinary
--  current-open checks.  This mirrors Loam's cancellation rule: an
--  interrupted completion may remain observationally open while still owning
--  the terminal decision for that Scheduled identity.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;

package HRA_N.Core.Scheduled_Retirement_Transition with
  SPARK_Mode => On
is
   pragma Pure;

   type Retirement_Transition_Status is
     (Retirement_Transitioned,
      Source_Retirements_Invalid,
      Source_Retirement_Full,
      Unknown_Scheduled_Id,
      Completion_Claim_Retained,
      Scheduled_Not_Current_Open);

   function Retirement_Sources_Are_Unique
     (Image : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Image.Ret_Count =>
        (for all J in I + 1 .. Image.Ret_Count =>
           not Equal_Token
             (Image.Ret_Items (I).Scheduled.Token,
              Image.Ret_Items (J).Scheduled.Token)));

   function Retirement_Source_Fresh
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (for all I in 1 .. Image.Ret_Count =>
        not Equal_Token
          (Image.Ret_Items (I).Scheduled.Token, Target.Token));

   --  This is intentionally separate from Is_Current_Open.  The production
   --  cancellation entrance must refuse any retained completion claim,
   --  including one whose Actual endpoint is still absent.
   function Completion_Claim_Absent
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (for all I in 1 .. Image.Comp_Count =>
        not Equal_Token
          (Image.Comp_Items (I).Scheduled.Token, Target.Token));

   function Replacement_Source_Absent
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (for all I in 1 .. Image.Repl_Count =>
        not Equal_Token
          (Image.Repl_Items (I).Original.Token, Target.Token));

   function No_Noncompletion_Terminal_For
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (Retirement_Source_Fresh (Image, Target)
      and then Replacement_Source_Absent (Image, Target));

   function Occurrence_Evidence_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (Target.Sched_Count = Source.Sched_Count
      and then
        (for all I in 1 .. Source.Sched_Count =>
           Target.Sched_Items (I) = Source.Sched_Items (I)));

   function Retirement_Prefix_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Source.Ret_Count =>
        Target.Ret_Items (I) = Source.Ret_Items (I));

   function Other_Terminal_Evidence_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (Target.Comp_Count = Source.Comp_Count
      and then Target.Repl_Count = Source.Repl_Count
      and then
        (for all I in 1 .. Source.Comp_Count =>
           Target.Comp_Items (I) = Source.Comp_Items (I))
      and then
        (for all I in 1 .. Source.Repl_Count =>
           Target.Repl_Items (I) = Source.Repl_Items (I)));

   function One_Fresh_Retirement
     (Source : Scheduled_Lifecycle;
      Added  : Retirement_Record;
      Target : Scheduled_Lifecycle) return Boolean is
     (Retirement_Sources_Are_Unique (Source)
      and then Source.Ret_Count < Max_Scheduled_Entries
      and then Sched_Exists (Source, Added.Scheduled)
      and then Completion_Claim_Absent (Source, Added.Scheduled)
      and then No_Noncompletion_Terminal_For (Source, Added.Scheduled)
      and then Occurrence_Evidence_Preserved (Source, Target)
      and then Target.Ret_Count = Source.Ret_Count + 1
      and then Retirement_Prefix_Preserved (Source, Target)
      and then Target.Ret_Items (Target.Ret_Count) = Added
      and then Other_Terminal_Evidence_Preserved (Source, Target)
      and then Retirement_Sources_Are_Unique (Target));

   procedure Append_Fresh_Retirement
     (Source : Scheduled_Lifecycle;
      Added  : Retirement_Record;
      Target : out Scheduled_Lifecycle;
      Status : out Retirement_Transition_Status)
   with
     Post =>
       (if not Retirement_Sources_Are_Unique (Source) then
           Status = Source_Retirements_Invalid
        elsif Source.Ret_Count = Max_Scheduled_Entries then
           Status = Source_Retirement_Full
        elsif not Sched_Exists (Source, Added.Scheduled) then
           Status = Unknown_Scheduled_Id
        elsif not Completion_Claim_Absent (Source, Added.Scheduled) then
           Status = Completion_Claim_Retained
        elsif not No_Noncompletion_Terminal_For
          (Source, Added.Scheduled)
        then
           Status = Scheduled_Not_Current_Open
        else
           Status = Retirement_Transitioned
           and then One_Fresh_Retirement (Source, Added, Target));

end HRA_N.Core.Scheduled_Retirement_Transition;
