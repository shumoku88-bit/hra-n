-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Scheduled_Replacement_Transition
--
--  Bounded proof-facing semantics for one canonical Scheduled replacement.
--
--  Replacement is one atomic semantic step:
--    1. append one fresh practical Scheduled occurrence;
--    2. append one terminal relation from the current-open source to that
--       fresh occurrence.
--
--  The relation proves exact evidence preservation and endpoint uniqueness.
--  The source graph must already be acyclic, and the fresh successor has no
--  outgoing replacement edge in the target.  Production admission separately
--  rechecks the complete lifecycle graph after serialization.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Creation_Transition;
use HRA_N.Core.Scheduled_Creation_Transition;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Scheduled_Replacement_Transition with
  SPARK_Mode => On
is
   pragma Pure;

   type Replacement_Transition_Status is
     (Replacement_Transitioned,
      Source_Lifecycle_Invalid,
      Source_Replacement_Full,
      Unknown_Scheduled_Source,
      Scheduled_Source_Not_Current_Open,
      Added_Occurrence_Rejected);

   function Replacement_Relations_Are_One_To_One
     (Image : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Image.Repl_Count =>
        (for all J in I + 1 .. Image.Repl_Count =>
           not Equal_Token
             (Image.Repl_Items (I).Original.Token,
              Image.Repl_Items (J).Original.Token)
           and then
           not Equal_Token
             (Image.Repl_Items (I).Replaced_By.Token,
              Image.Repl_Items (J).Replaced_By.Token)));

   function Replacement_Source_Fresh
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (for all I in 1 .. Image.Repl_Count =>
        not Equal_Token
          (Image.Repl_Items (I).Original.Token, Target.Token));

   function Replacement_Target_Fresh
     (Image  : Scheduled_Lifecycle;
      Target : Scheduled_Id) return Boolean is
     (for all I in 1 .. Image.Repl_Count =>
        not Equal_Token
          (Image.Repl_Items (I).Replaced_By.Token, Target.Token));

   function Source_Admitted_For_Replacement
     (Image : Scheduled_Lifecycle) return Boolean is
     (Occurrence_Image_Admitted (Image)
      and then Completions_Reference_Known (Image)
      and then Retirements_Reference_Known (Image)
      and then Replacements_Reference_Known (Image)
      and then Terminal_Evidence_Compatible (Image)
      and then Replacement_Terminal_Compatible (Image)
      and then Replacement_Relations_Are_One_To_One (Image)
      and then Terminal_Targets_Are_Unique (Image)
      and then Replacement_History_Is_Acyclic (Image));

   function Other_Terminal_Evidence_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (Target.Comp_Count = Source.Comp_Count
      and then Target.Ret_Count = Source.Ret_Count
      and then
        (for all I in 1 .. Source.Comp_Count =>
           Target.Comp_Items (I) = Source.Comp_Items (I))
      and then
        (for all I in 1 .. Source.Ret_Count =>
           Target.Ret_Items (I) = Source.Ret_Items (I)));

   function Replacement_Prefix_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Source.Repl_Count =>
        Target.Repl_Items (I) = Source.Repl_Items (I));

   function Successor_Has_No_Outgoing_Replacement
     (Image     : Scheduled_Lifecycle;
      Successor : Scheduled_Id) return Boolean is
     (for all I in 1 .. Image.Repl_Count =>
        not Equal_Token
          (Image.Repl_Items (I).Original.Token, Successor.Token));

   function One_Fresh_Replacement
     (Source     : Scheduled_Lifecycle;
      Original   : Scheduled_Id;
      Successor  : Scheduled_Occurrence;
      Target     : Scheduled_Lifecycle) return Boolean is
     (Source_Admitted_For_Replacement (Source)
      and then Source.Sched_Count < Max_Scheduled_Entries
      and then Source.Repl_Count < Max_Scheduled_Entries
      and then Sched_Exists (Source, Original)
      and then Is_Current_Open (Source, Original)
      and then Practical_Creation (Successor)
      and then Fresh_For (Source, Successor)
      and then Replacement_Source_Fresh (Source, Original)
      and then Replacement_Source_Fresh (Source, Successor.Id)
      and then Replacement_Target_Fresh (Source, Successor.Id)
      and then Target.Sched_Count = Source.Sched_Count + 1
      and then Occurrence_Prefix_Preserved (Source, Target)
      and then Target.Sched_Items (Target.Sched_Count) = Successor
      and then Occurrence_Ids_Are_Unique (Target)
      and then Other_Terminal_Evidence_Preserved (Source, Target)
      and then Target.Repl_Count = Source.Repl_Count + 1
      and then Replacement_Prefix_Preserved (Source, Target)
      and then Target.Repl_Items (Target.Repl_Count) =
        (Original => Original, Replaced_By => Successor.Id)
      and then Replacement_Relations_Are_One_To_One (Target)
      and then Successor_Has_No_Outgoing_Replacement
        (Target, Successor.Id));

   procedure Append_Fresh_Replacement
     (Source    : Scheduled_Lifecycle;
      Original  : Scheduled_Id;
      Successor : Scheduled_Occurrence;
      Target    : out Scheduled_Lifecycle;
      Status    : out Replacement_Transition_Status)
   with
     Post =>
       (if not Source_Admitted_For_Replacement (Source) then
           Status = Source_Lifecycle_Invalid
        elsif Source.Repl_Count = Max_Scheduled_Entries then
           Status = Source_Replacement_Full
        elsif not Sched_Exists (Source, Original) then
           Status = Unknown_Scheduled_Source
        elsif not Is_Current_Open (Source, Original)
          or else not Replacement_Source_Fresh (Source, Original)
        then
           Status = Scheduled_Source_Not_Current_Open
        elsif Source.Sched_Count = Max_Scheduled_Entries
          or else not Practical_Creation (Successor)
          or else not Fresh_For (Source, Successor)
          or else not Replacement_Source_Fresh (Source, Successor.Id)
          or else not Replacement_Target_Fresh (Source, Successor.Id)
        then
           Status = Added_Occurrence_Rejected
        else
           Status = Replacement_Transitioned
           and then
             One_Fresh_Replacement
               (Source, Original, Successor, Target));

end HRA_N.Core.Scheduled_Replacement_Transition;
