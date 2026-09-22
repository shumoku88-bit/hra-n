-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Scheduled_Creation_Transition
--
--  Bounded proof-facing semantics for one canonical Scheduled creation.
--
--  The theorem boundary is intentionally smaller than the production writer:
--  it proves occurrence append semantics and exact preservation of retained
--  terminal evidence.  Filesystem ownership/durability, Locus admission, raw
--  terminal application-readability, and production working-set size remain
--  separate runtime qualification boundaries.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;

package HRA_N.Core.Scheduled_Creation_Transition with
  SPARK_Mode => On
is
   pragma Pure;

   type Creation_Transition_Status is
     (Creation_Transitioned,
      Source_Occurrences_Invalid,
      Source_Full,
      Added_Not_Practical,
      Duplicate_Scheduled_Id);

   --  Proof-facing identity law stated directly as a quantified expression.
   --  Keeping it local avoids making this transition depend on the executable
   --  loop implementation of Scheduled_Ids_Are_Unique.
   function Occurrence_Ids_Are_Unique
     (Image : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Image.Sched_Count =>
        (for all J in I + 1 .. Image.Sched_Count =>
           not Equal_Token
             (Image.Sched_Items (I).Id.Token,
              Image.Sched_Items (J).Id.Token)));

   --  Semantic admission for the occurrence plane represented by this proof
   --  model.  Empty historical balanced movements remain admissible: Loam's
   --  codec permits them.  The stronger nonempty/nonzero rule applies only to
   --  a newly published practical creation.
   function Occurrence_Image_Admitted
     (Image : Scheduled_Lifecycle) return Boolean is
     (Occurrence_Ids_Are_Unique (Image)
      and then
        (for all I in 1 .. Image.Sched_Count =>
           Is_Conserved (Image.Sched_Items (I))));

   function Fresh_For
     (Source : Scheduled_Lifecycle;
      Added  : Scheduled_Occurrence) return Boolean is
     (for all I in 1 .. Source.Sched_Count =>
        not Equal_Token
          (Source.Sched_Items (I).Id.Token, Added.Id.Token));

   --  The production creation entrance currently admits exactly this
   --  practical semantic shape before representation-specific token checks.
   function Practical_Creation
     (Added : Scheduled_Occurrence) return Boolean is
     (Added.Id.Token.Length > 0
      and then Is_Valid_Date
        (Added.Expected_Day.Year,
         Added.Expected_Day.Month,
         Added.Expected_Day.Day)
      and then Equal_Token (Added.Measure.Token, Make_Token ("jpy"))
      and then Added.Changes.Count > 0
      and then
        (for all I in 1 .. Added.Changes.Count =>
           Added.Changes.Values (I).Amount /= 0)
      and then Is_Conserved (Added));

   function Occurrence_Prefix_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Source.Sched_Count =>
        Target.Sched_Items (I) = Source.Sched_Items (I));

   --  Creation must not reinterpret any existing terminal evidence.  This is
   --  stronger than merely preserving current-open answers: the exact active
   --  Completion, Retirement, and Replacement rows remain unchanged.
   function Terminal_Evidence_Preserved
     (Source : Scheduled_Lifecycle;
      Target : Scheduled_Lifecycle) return Boolean is
     (Target.Comp_Count = Source.Comp_Count
      and then Target.Ret_Count = Source.Ret_Count
      and then Target.Repl_Count = Source.Repl_Count
      and then
        (for all I in 1 .. Source.Comp_Count =>
           Target.Comp_Items (I) = Source.Comp_Items (I))
      and then
        (for all I in 1 .. Source.Ret_Count =>
           Target.Ret_Items (I) = Source.Ret_Items (I))
      and then
        (for all I in 1 .. Source.Repl_Count =>
           Target.Repl_Items (I) = Source.Repl_Items (I)));

   function One_Fresh_Creation
     (Source : Scheduled_Lifecycle;
      Added  : Scheduled_Occurrence;
      Target : Scheduled_Lifecycle) return Boolean is
     (Occurrence_Image_Admitted (Source)
      and then Source.Sched_Count < Max_Scheduled_Entries
      and then Practical_Creation (Added)
      and then Fresh_For (Source, Added)
      and then Target.Sched_Count = Source.Sched_Count + 1
      and then Occurrence_Prefix_Preserved (Source, Target)
      and then Target.Sched_Items (Target.Sched_Count) = Added
      and then Terminal_Evidence_Preserved (Source, Target)
      and then Occurrence_Ids_Are_Unique (Target));

   procedure Append_Fresh_Creation
     (Source : Scheduled_Lifecycle;
      Added  : Scheduled_Occurrence;
      Target : out Scheduled_Lifecycle;
      Status : out Creation_Transition_Status)
   with
     Post =>
       (if not Occurrence_Image_Admitted (Source) then
           Status = Source_Occurrences_Invalid
        elsif Source.Sched_Count = Max_Scheduled_Entries then
           Status = Source_Full
        elsif not Practical_Creation (Added) then
           Status = Added_Not_Practical
        elsif not Fresh_For (Source, Added) then
           Status = Duplicate_Scheduled_Id
        else
           Status = Creation_Transitioned
           and then One_Fresh_Creation (Source, Added, Target));

end HRA_N.Core.Scheduled_Creation_Transition;
