with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Completion_Transition;
use HRA_N.Core.Scheduled_Completion_Transition;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with Test_Support;        use Test_Support;

package body Test_Scheduled_Completion_Transition is

   Empty_Change : constant Scheduled_Change :=
     (Locus => (Token => Make_Token ("")), Amount => 0);

   Empty_Occurrence : constant Scheduled_Occurrence :=
     (Id           => (Token => Make_Token ("")),
      Expected_Day => (Year => 2026, Month => 1, Day => 1),
      Measure      => (Token => Make_Token ("")),
      Changes      =>
        (Count  => 0,
         Values => [others => Empty_Change]));

   Empty_Completion : constant Completion_Record :=
     (Scheduled => (Token => Make_Token ("")),
      Actual    => (Token => Make_Token ("")));

   Empty_Retirement : constant Retirement_Record :=
     (Scheduled => (Token => Make_Token ("")));

   Empty_Replacement : constant Replacement_Record :=
     (Original    => (Token => Make_Token ("")),
      Replaced_By => (Token => Make_Token ("")));

   function Occurrence (Id_Text : String) return Scheduled_Occurrence is
      Changes : Change_List :=
        (Count  => 2,
         Values => [others => Empty_Change]);
   begin
      Changes.Values (1) :=
        (Locus => (Token => Make_Token ("cash")), Amount => -10);
      Changes.Values (2) :=
        (Locus => (Token => Make_Token ("food")), Amount => 10);
      return
        (Id           => (Token => Make_Token (Id_Text)),
         Expected_Day => (Year => 2026, Month => 9, Day => 23),
         Measure      => (Token => Make_Token ("jpy")),
         Changes      => Changes);
   end Occurrence;

   procedure Run is
      S1 : constant Scheduled_Occurrence := Occurrence ("scheduled-1");
      S2 : constant Scheduled_Occurrence := Occurrence ("scheduled-2");
      Existing : constant Completion_Record :=
        (Scheduled => (Token => Make_Token ("scheduled-1")),
         Actual    => (Token => Make_Token ("scheduled-completion:scheduled-1")));
      Added : constant Completion_Record :=
        (Scheduled => (Token => Make_Token ("scheduled-2")),
         Actual    => (Token => Make_Token ("scheduled-completion:scheduled-2")));

      Source : constant Scheduled_Lifecycle :=
        (Sched_Count => 2,
         Sched_Items =>
           [1 => S1,
            2 => S2,
            others => Empty_Occurrence],
         Comp_Count => 1,
         Comp_Items =>
           [1 => Existing,
            others => Empty_Completion],
         Ret_Count => 0,
         Ret_Items => [others => Empty_Retirement],
         Repl_Count => 0,
         Repl_Items => [others => Empty_Replacement]);

      Target : Scheduled_Lifecycle;
      Status : Completion_Transition_Status;
   begin
      Append_Fresh_Completion (Source, Added, Target, Status);

      Assert
        (Status = Completion_Transitioned,
         "fresh Scheduled completion transition succeeds");
      Assert
        (One_Fresh_Completion (Source, Added, Target),
         "successful transition establishes one-fresh completion relation");
      Assert_Equal_Int
        (2, Long_Long_Integer (Target.Comp_Count),
         "transition adds exactly one completion claim");
      Assert
        (Target.Comp_Items (1) = Existing
         and then Target.Comp_Items (2) = Added,
         "transition preserves prior completion and appends exact new pair");
      Assert
        (Target.Sched_Count = Source.Sched_Count
         and then Target.Sched_Items (1) = Source.Sched_Items (1)
         and then Target.Sched_Items (2) = Source.Sched_Items (2),
         "completion does not rewrite Scheduled occurrences");
      Assert
        (Other_Terminal_Evidence_Preserved (Source, Target),
         "completion preserves retirement and replacement evidence");
      Assert
        (Completion_Pairs_Are_One_To_One (Target),
         "completion preserves one-to-one endpoint ownership");

      declare
         Duplicate_Endpoint : constant Completion_Record :=
           (Scheduled => (Token => Make_Token ("scheduled-2")),
            Actual    => Existing.Actual);
      begin
         Append_Fresh_Completion
           (Source, Duplicate_Endpoint, Target, Status);
         Assert
           (Status = Actual_Endpoint_Already_Claimed,
            "Actual endpoint already owned by another completion is rejected");
      end;

      declare
         Already_Closed : constant Completion_Record :=
           (Scheduled => Existing.Scheduled,
            Actual    => (Token => Make_Token ("another-actual")));
      begin
         Append_Fresh_Completion
           (Source, Already_Closed, Target, Status);
         Assert
           (Status = Scheduled_Not_Current_Open,
            "Scheduled source with terminal evidence cannot be completed again");
      end;

      declare
         Unknown : constant Completion_Record :=
           (Scheduled => (Token => Make_Token ("scheduled-missing")),
            Actual    => (Token => Make_Token ("missing-actual")));
      begin
         Append_Fresh_Completion (Source, Unknown, Target, Status);
         Assert
           (Status = Unknown_Scheduled_Id,
            "unknown Scheduled source is rejected");
      end;

      declare
         Invalid : Scheduled_Lifecycle := Source;
      begin
         Invalid.Comp_Count := 2;
         Invalid.Comp_Items (2) :=
           (Scheduled => (Token => Make_Token ("scheduled-1")),
            Actual    => (Token => Make_Token ("other-actual")));
         Append_Fresh_Completion (Invalid, Added, Target, Status);
         Assert
           (Status = Source_Completions_Invalid,
            "non-one-to-one source completion image fails closed");
      end;
   end Run;

end Test_Scheduled_Completion_Transition;
