with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Replacement_Transition;
use HRA_N.Core.Scheduled_Replacement_Transition;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with Test_Support;        use Test_Support;

package body Test_Scheduled_Replacement_Transition is

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

   function Occurrence
     (Id_Text : String;
      Day     : Day_Type := 23) return Scheduled_Occurrence
   is
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
         Expected_Day => (Year => 2026, Month => 9, Day => Day),
         Measure      => (Token => Make_Token ("jpy")),
         Changes      => Changes);
   end Occurrence;

   procedure Run is
      S1 : constant Scheduled_Occurrence :=
        Occurrence ("scheduled-1", 20);
      S2 : constant Scheduled_Occurrence :=
        Occurrence ("scheduled-2", 23);
      S3 : constant Scheduled_Occurrence :=
        Occurrence ("scheduled-3", 25);

      Source : constant Scheduled_Lifecycle :=
        (Sched_Count => 2,
         Sched_Items =>
           [1 => S1,
            2 => S2,
            others => Empty_Occurrence],
         Comp_Count => 0,
         Comp_Items => [others => Empty_Completion],
         Ret_Count => 0,
         Ret_Items => [others => Empty_Retirement],
         Repl_Count => 1,
         Repl_Items =>
           [1 =>
              (Original    => (Token => Make_Token ("scheduled-1")),
               Replaced_By => (Token => Make_Token ("scheduled-2"))),
            others => Empty_Replacement]);

      Original : constant Scheduled_Id :=
        (Token => Make_Token ("scheduled-2"));
      Target : Scheduled_Lifecycle;
      Status : Replacement_Transition_Status;
   begin
      Assert
        (Source_Admitted_For_Replacement (Source),
         "replacement fixture starts from admitted lifecycle evidence");
      Assert
        (Is_Current_Open (Source, Original),
         "replacement source is current-open");

      Append_Fresh_Replacement
        (Source, Original, S3, Target, Status);

      Assert
        (Status = Replacement_Transitioned,
         "fresh Scheduled replacement transition succeeds");
      Assert
        (One_Fresh_Replacement (Source, Original, S3, Target),
         "successful transition establishes one-fresh replacement relation");
      Assert_Equal_Int
        (3, Long_Long_Integer (Target.Sched_Count),
         "replacement appends exactly one Scheduled occurrence");
      Assert_Equal_Int
        (2, Long_Long_Integer (Target.Repl_Count),
         "replacement appends exactly one terminal relation");
      Assert
        (Target.Sched_Items (3) = S3,
         "replacement retains exact fresh successor occurrence");
      Assert
        (Target.Repl_Items (1) = Source.Repl_Items (1)
         and then
           Target.Repl_Items (2) =
             (Original    => Original,
              Replaced_By => S3.Id),
         "replacement preserves prior relation and appends exact new edge");
      Assert
        (Replacement_Relations_Are_One_To_One (Target),
         "replacement preserves one-to-one endpoint ownership");
      Assert
        (Successor_Has_No_Outgoing_Replacement (Target, S3.Id),
         "fresh successor has no outgoing replacement edge");
      Assert
        (Replacement_History_Is_Acyclic (Target),
         "fresh successor extension remains acyclic in executable lifecycle law");

      declare
         Retired : Scheduled_Lifecycle := Source;
      begin
         Retired.Ret_Count := 1;
         Retired.Ret_Items (1) := (Scheduled => Original);
         Append_Fresh_Replacement
           (Retired, Original, S3, Target, Status);
         Assert
           (Status = Scheduled_Source_Not_Current_Open,
            "retired Scheduled source cannot be replaced");
      end;

      declare
         Unknown : constant Scheduled_Id :=
           (Token => Make_Token ("scheduled-missing"));
      begin
         Append_Fresh_Replacement
           (Source, Unknown, S3, Target, Status);
         Assert
           (Status = Unknown_Scheduled_Source,
            "unknown Scheduled source is rejected");
      end;

      declare
         Duplicate : constant Scheduled_Occurrence :=
           Occurrence ("scheduled-1", 25);
      begin
         Append_Fresh_Replacement
           (Source, Original, Duplicate, Target, Status);
         Assert
           (Status = Added_Occurrence_Rejected,
            "replacement successor identity must be fresh");
      end;

      declare
         Invalid : Scheduled_Lifecycle := Source;
      begin
         Invalid.Repl_Count := 2;
         Invalid.Repl_Items (2) :=
           (Original    => (Token => Make_Token ("scheduled-1")),
            Replaced_By => (Token => Make_Token ("scheduled-2")));
         Append_Fresh_Replacement
           (Invalid, Original, S3, Target, Status);
         Assert
           (Status = Source_Lifecycle_Invalid,
            "invalid source replacement ownership fails closed");
      end;
   end Run;

end Test_Scheduled_Replacement_Transition;
