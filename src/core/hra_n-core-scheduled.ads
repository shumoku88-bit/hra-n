-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Scheduled
--
--  Scheduled Movement lifecycle and open-obligation inspection.
--  Encodes Loam's 4-phase lifecycle ontology:
--    Scheduled   : Authoritative planned movements with expected occurrence date.
--    Completion  : Terminal evidence binding a ScheduledId to an Actual EventId.
--    Retirement  : Terminal cancellation evidence withdrawing an obligation.
--    Replacement : Terminal replacement evidence pointing to a successor plan.
--
--  Invariants:
--    A Scheduled movement is 'current-open' if and only if it is neither
--    completed, retired, nor replaced.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Core.Scheduled with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Scheduled_Entries : constant := 128;
   Max_Changes_Per_Sched : constant := 8;

   subtype Scheduled_Count_Type is Natural range 0 .. Max_Scheduled_Entries;
   subtype Scheduled_Index_Type is Positive range 1 .. Max_Scheduled_Entries;

   subtype Change_Count_Type is Natural range 0 .. Max_Changes_Per_Sched;
   subtype Change_Index_Type is Positive range 1 .. Max_Changes_Per_Sched;

   --  Distinct identifier for a scheduled movement occurrence (e.g. scheduled-3)
   type Scheduled_Id is record
      Token : Token_Text;
   end record;

   --  A single quantity change at a locus coordinate
   type Scheduled_Change is record
      Locus  : Locus_Id;
      Amount : Quanta_Type := 0;
   end record;

   type Change_Array is array (Change_Index_Type) of Scheduled_Change;

   type Change_List is record
      Count  : Change_Count_Type := 0;
      Values : Change_Array      := [others => (Locus => (Token => (0, [others => ' '])), Amount => 0)];
   end record;

   --  One planned movement occurrence
   type Scheduled_Occurrence is record
      Id           : Scheduled_Id;
      Expected_Day : Date_Type;
      Measure      : Measure_Id;
      Changes      : Change_List;
   end record;

   type Occurrence_Array is array (Scheduled_Index_Type) of Scheduled_Occurrence;

   --  Terminal Evidence Records
   type Completion_Record is record
      Scheduled : Scheduled_Id;
      Actual    : Event_Id;
   end record;

   type Completion_Array is array (Scheduled_Index_Type) of Completion_Record;

   type Retirement_Record is record
      Scheduled : Scheduled_Id;
   end record;

   type Retirement_Array is array (Scheduled_Index_Type) of Retirement_Record;

   type Replacement_Record is record
      Original    : Scheduled_Id;
      Replaced_By : Scheduled_Id;
   end record;

   type Replacement_Array is array (Scheduled_Index_Type) of Replacement_Record;

   --  Complete 4-phase Lifecycle Image
   type Scheduled_Lifecycle is record
      Sched_Count : Scheduled_Count_Type := 0;
      Sched_Items : Occurrence_Array;

      Comp_Count  : Scheduled_Count_Type := 0;
      Comp_Items  : Completion_Array;

      Ret_Count   : Scheduled_Count_Type := 0;
      Ret_Items   : Retirement_Array;

      Repl_Count  : Scheduled_Count_Type := 0;
      Repl_Items  : Replacement_Array;
   end record;

   type Lookup_Result is record
      Found : Boolean := False;
      Item  : Scheduled_Occurrence;
   end record;

   ----------------------------------------------------------------------------
   --  Specification Functions & Predicates
   ----------------------------------------------------------------------------

   function Scheduled_Ids_Are_Unique
     (Lifecycle : Scheduled_Lifecycle) return Boolean;

   --  A declaration can have at most one terminal fact of any kind.
   function Terminal_Targets_Are_Unique
     (Lifecycle : Scheduled_Lifecycle) return Boolean;

   function Replacement_History_Is_Acyclic
     (Lifecycle : Scheduled_Lifecycle) return Boolean;

   --  Check if a ScheduledId has a recorded completion
   function Is_Completed
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id) return Boolean is
     (for some I in 1 .. Lifecycle.Comp_Count =>
        Equal_Token (Lifecycle.Comp_Items (I).Scheduled.Token, Target.Token));

   --  Check if a ScheduledId has a recorded retirement (cancellation)
   function Is_Retired
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id) return Boolean is
     (for some I in 1 .. Lifecycle.Ret_Count =>
        Equal_Token (Lifecycle.Ret_Items (I).Scheduled.Token, Target.Token));

   --  Check if a ScheduledId has been replaced by another
   function Is_Replaced
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id) return Boolean is
     (for some I in 1 .. Lifecycle.Repl_Count =>
        Equal_Token (Lifecycle.Repl_Items (I).Original.Token, Target.Token));

   --  Core open-world invariant: current-open requires no terminal evidence
   function Is_Current_Open
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id) return Boolean is
     (not Is_Completed (Lifecycle, Target)
      and then not Is_Retired (Lifecycle, Target)
      and then not Is_Replaced (Lifecycle, Target));

   --  Lookup occurrence by ID
   function Find_Occurrence
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id) return Lookup_Result;

   --  Check whether target scheduled ID exists among scheduled occurrences
   function Sched_Exists
     (Lifecycle : Scheduled_Lifecycle;
      Target    : Scheduled_Id) return Boolean is
     (for some I in 1 .. Lifecycle.Sched_Count =>
        Equal_Token (Lifecycle.Sched_Items (I).Id.Token, Target.Token));

   --  Structural integrity: every completion references a retained occurrence
   function Completions_Reference_Known
     (Lifecycle : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Lifecycle.Comp_Count =>
        Sched_Exists (Lifecycle, Lifecycle.Comp_Items (I).Scheduled));

   --  Structural integrity: every retirement references a retained occurrence
   function Retirements_Reference_Known
     (Lifecycle : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Lifecycle.Ret_Count =>
        Sched_Exists (Lifecycle, Lifecycle.Ret_Items (I).Scheduled));

   --  Structural integrity: every replacement references retained occurrences at both endpoints
   function Replacements_Reference_Known
     (Lifecycle : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Lifecycle.Repl_Count =>
        Sched_Exists (Lifecycle, Lifecycle.Repl_Items (I).Original)
        and then Sched_Exists (Lifecycle, Lifecycle.Repl_Items (I).Replaced_By));

   --  Terminal evidence compatibility: no scheduled ID has both completion and retirement
   function Terminal_Evidence_Compatible
     (Lifecycle : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Lifecycle.Ret_Count =>
        not Is_Completed (Lifecycle, Lifecycle.Ret_Items (I).Scheduled));

   --  Replacement compatibility: no replacement source has completion or retirement
   function Replacement_Terminal_Compatible
     (Lifecycle : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Lifecycle.Repl_Count =>
        not Is_Completed (Lifecycle, Lifecycle.Repl_Items (I).Original)
        and then not Is_Retired (Lifecycle, Lifecycle.Repl_Items (I).Original));

   --  Replacements are one-to-one at both endpoints
   function Replacements_Are_One_To_One
     (Lifecycle : Scheduled_Lifecycle) return Boolean is
     (for all I in 1 .. Lifecycle.Repl_Count =>
        (for all J in I + 1 .. Lifecycle.Repl_Count =>
           not Equal_Token (Lifecycle.Repl_Items (I).Original.Token,
                            Lifecycle.Repl_Items (J).Original.Token)
           and then
           not Equal_Token (Lifecycle.Repl_Items (I).Replaced_By.Token,
                            Lifecycle.Repl_Items (J).Replaced_By.Token)));

   --  Sum of all changes at a specified locus in an occurrence
   function Quantity_At
     (Occ   : Scheduled_Occurrence;
      Locus : Locus_Id) return Quanta_Type;

end HRA_N.Core.Scheduled;
