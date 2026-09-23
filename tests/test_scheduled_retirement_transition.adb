with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Retirement_Transition;
use HRA_N.Core.Scheduled_Retirement_Transition;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with Test_Support;        use Test_Support;

package body Test_Scheduled_Retirement_Transition is

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
      S3 : constant Scheduled_Occurrence := Occurrence ("scheduled-3");

      Source : constant Scheduled_Lifecycle :=
        (Sched_Count => 3,
         Sched_Items =>
           [1 => S1,
            2 => S2,
            3 => S3,
            others => Empty_Occurrence],
         Comp_Count => 0,
         Comp_Items => [others => Empty_Completion],
         Ret_Count => 1,
         Ret_Items =>
           [1 => (Scheduled => (Token => Make_Token ("scheduled-1"))),
            others => Empty_Retirement],
         Repl_Count => 0,
         Repl_Items => [others => Empty_Replacement]);

      Added : constant Retirement_Record :=
        (Scheduled => (Token => Make_Token ("scheduled-2")));
      Target : Scheduled_Lifecycle;
      Status : Retirement_Transition_Status;
   begin
      Append_Fresh_Retirement (Source, Added, Target, Status);

      Assert
        (Status = Retirement_Transitioned,
         "fresh Scheduled retirement transition succeeds");
      Assert
        (One_Fresh_Retirement (Source, Added, Target),
         "successful transition establishes one-fresh retirement relation");
      Assert_Equal_Int
        (2, Long_Long_Integer (Target.Ret_Count),
         "transition adds exactly one retirement row");
      Assert
        (Target.Ret_Items (1) = Source.Ret_Items (1)
         and then Target.Ret_Items (2) = Added,
         "transition preserves prior retirement and appends exact target");
      Assert
        (Occurrence_Evidence_Preserved (Source, Target),
         "retirement preserves Scheduled occurrence evidence");
      Assert
        (Other_Terminal_Evidence_Preserved (Source, Target),
         "retirement preserves completion and replacement evidence");
      Assert
        (Retirement_Sources_Are_Unique (Target),
         "retirement preserves unique terminal source ownership");

      declare
         Interrupted : Scheduled_Lifecycle := Source;
      begin
         Interrupted.Comp_Count := 1;
         Interrupted.Comp_Items (1) :=
           (Scheduled => (Token => Make_Token ("scheduled-2")),
            Actual =>
              (Token =>
                 Make_Token ("scheduled-completion:scheduled-2")));
         Append_Fresh_Retirement
           (Interrupted, Added, Target, Status);
         Assert
           (Status = Completion_Claim_Retained,
            "retained completion claim blocks retirement before open checks");
      end;

      declare
         Already_Retired : constant Retirement_Record :=
           (Scheduled => (Token => Make_Token ("scheduled-1")));
      begin
         Append_Fresh_Retirement
           (Source, Already_Retired, Target, Status);
         Assert
           (Status = Scheduled_Not_Current_Open,
            "already retired Scheduled identity is rejected");
      end;

      declare
         Replaced : Scheduled_Lifecycle := Source;
      begin
         Replaced.Repl_Count := 1;
         Replaced.Repl_Items (1) :=
           (Original    => (Token => Make_Token ("scheduled-2")),
            Replaced_By => (Token => Make_Token ("scheduled-3")));
         Append_Fresh_Retirement (Replaced, Added, Target, Status);
         Assert
           (Status = Scheduled_Not_Current_Open,
            "replaced Scheduled identity is rejected");
      end;

      declare
         Unknown : constant Retirement_Record :=
           (Scheduled => (Token => Make_Token ("scheduled-missing")));
      begin
         Append_Fresh_Retirement (Source, Unknown, Target, Status);
         Assert
           (Status = Unknown_Scheduled_Id,
            "unknown Scheduled identity is rejected");
      end;

      declare
         Invalid : Scheduled_Lifecycle := Source;
      begin
         Invalid.Ret_Count := 2;
         Invalid.Ret_Items (2) := Invalid.Ret_Items (1);
         Append_Fresh_Retirement (Invalid, Added, Target, Status);
         Assert
           (Status = Source_Retirements_Invalid,
            "duplicate source retirement evidence fails closed");
      end;
   end Run;

end Test_Scheduled_Retirement_Transition;
