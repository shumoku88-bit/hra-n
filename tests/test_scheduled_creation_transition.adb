with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Creation_Transition;
use HRA_N.Core.Scheduled_Creation_Transition;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with Test_Support;        use Test_Support;

package body Test_Scheduled_Creation_Transition is

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
      Amount  : Quanta_Type) return Scheduled_Occurrence
   is
      Changes : Change_List :=
        (Count  => 2,
         Values => [others => Empty_Change]);
   begin
      Changes.Values (1) :=
        (Locus => (Token => Make_Token ("cash")),
         Amount => -Amount);
      Changes.Values (2) :=
        (Locus => (Token => Make_Token ("food")),
         Amount => Amount);
      return
        (Id           => (Token => Make_Token (Id_Text)),
         Expected_Day => (Year => 2026, Month => 9, Day => 22),
         Measure      => (Token => Make_Token ("jpy")),
         Changes      => Changes);
   end Occurrence;

   procedure Run is
      S1 : constant Scheduled_Occurrence :=
        Occurrence ("scheduled-1", 10);
      S2 : constant Scheduled_Occurrence :=
        Occurrence ("scheduled-2", 20);
      S3 : constant Scheduled_Occurrence :=
        Occurrence ("scheduled-3", 30);

      Source : constant Scheduled_Lifecycle :=
        (Sched_Count => 2,
         Sched_Items =>
           [1 => S1,
            2 => S2,
            others => Empty_Occurrence],
         Comp_Count => 0,
         Comp_Items => [others => Empty_Completion],
         Ret_Count => 1,
         Ret_Items =>
           [1 => (Scheduled => (Token => Make_Token ("scheduled-1"))),
            others => Empty_Retirement],
         Repl_Count => 0,
         Repl_Items => [others => Empty_Replacement]);

      Target : Scheduled_Lifecycle;
      Status : Creation_Transition_Status;
   begin
      Append_Fresh_Creation (Source, S3, Target, Status);

      Assert
        (Status = Creation_Transitioned,
         "fresh Scheduled creation transition succeeds");
      Assert
        (One_Fresh_Creation (Source, S3, Target),
         "successful transition establishes one-fresh creation relation");
      Assert_Equal_Int
        (3, Long_Long_Integer (Target.Sched_Count),
         "transition adds exactly one Scheduled occurrence");
      Assert
        (Target.Sched_Items (1) = S1
         and then Target.Sched_Items (2) = S2,
         "transition preserves complete prior occurrence prefix");
      Assert
        (Target.Sched_Items (3) = S3,
         "transition retains complete added occurrence");
      Assert
        (Occurrence_Image_Admitted (Target),
         "fresh creation preserves occurrence admission");
      Assert
        (Terminal_Evidence_Preserved (Source, Target),
         "fresh creation preserves exact terminal evidence");
      Assert
        (Target.Ret_Count = 1
         and then Equal_Token
           (Target.Ret_Items (1).Scheduled.Token,
            Make_Token ("scheduled-1")),
         "prior retirement evidence is unchanged");

      Append_Fresh_Creation (Source, S2, Target, Status);
      Assert
        (Status = Duplicate_Scheduled_Id,
         "duplicate Scheduled identity fails closed");

      declare
         Bad : Scheduled_Occurrence := S3;
      begin
         Bad.Changes.Values (1).Amount := -30;
         Bad.Changes.Values (2).Amount := 29;
         Append_Fresh_Creation (Source, Bad, Target, Status);
         Assert
           (Status = Added_Not_Practical,
            "unbalanced new Scheduled occurrence fails closed");
      end;

      declare
         Bad : Scheduled_Occurrence := S3;
      begin
         Bad.Measure := (Token => Make_Token ("usd"));
         Append_Fresh_Creation (Source, Bad, Target, Status);
         Assert
           (Status = Added_Not_Practical,
            "non-JPY practical creation is outside this transition");
      end;

      declare
         Invalid_Source : Scheduled_Lifecycle := Source;
      begin
         Invalid_Source.Sched_Items (2) := S1;
         Append_Fresh_Creation
           (Invalid_Source, S3, Target, Status);
         Assert
           (Status = Source_Occurrences_Invalid,
            "non-unique source occurrence image cannot transition");
      end;
   end Run;

end Test_Scheduled_Creation_Transition;
