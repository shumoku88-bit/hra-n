with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Completion_Protocol;
use HRA_N.Core.Scheduled_Completion_Protocol;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with Test_Support; use Test_Support;

package body Test_Scheduled_Completion_Protocol is

   Empty_Ev : constant Event :=
     Make_Event
       ((Token => Make_Token ("")),
        (Count => 0, Values => [others => Empty_Effect]));

   Empty_Change : constant Scheduled_Change :=
     (Locus => (Token => Make_Token ("")), Amount => 0);

   Empty_Occurrence : constant Scheduled_Occurrence :=
     (Id           => (Token => Make_Token ("")),
      Expected_Day => (Year => 2026, Month => 1, Day => 1),
      Measure      => (Token => Make_Token ("")),
      Changes      =>
        (Count => 0, Values => [others => Empty_Change]));

   Empty_Completion : constant Completion_Record :=
     (Scheduled => (Token => Make_Token ("")),
      Actual    => (Token => Make_Token ("")));

   Empty_Retirement : constant Retirement_Record :=
     (Scheduled => (Token => Make_Token ("")));

   Empty_Replacement : constant Replacement_Record :=
     (Original    => (Token => Make_Token ("")),
      Replaced_By => (Token => Make_Token ("")));

   function Planned return Scheduled_Occurrence is
      Changes : Change_List :=
        (Count => 2, Values => [others => Empty_Change]);
   begin
      Changes.Values (1) :=
        (Locus => (Token => Make_Token ("cash")), Amount => -50);
      Changes.Values (2) :=
        (Locus => (Token => Make_Token ("food")), Amount => 50);
      return
        (Id           => (Token => Make_Token ("scheduled-1")),
         Expected_Day => (Year => 2026, Month => 9, Day => 23),
         Measure      => (Token => Make_Token ("jpy")),
         Changes      => Changes);
   end Planned;

   function Completion_Event return Event is
      Effects : Effect_List :=
        (Count => 2, Values => [others => Empty_Effect]);
   begin
      Effects.Values (1) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("cash")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => -50));
      Effects.Values (2) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("food")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => 50));
      return
        Make_Event
          ((Token => Make_Token ("scheduled-completion:scheduled-1")),
           Effects);
   end Completion_Event;

   procedure Run is
      Planned_Item : constant Scheduled_Occurrence := Planned;
      Added_Actual : constant Event := Completion_Event;
      Claim : constant Completion_Record :=
        (Scheduled => Planned_Item.Id,
         Actual    => HRA_N.Core.Event.Id (Added_Actual));

      Scheduled_Before : constant Scheduled_Lifecycle :=
        (Sched_Count => 1,
         Sched_Items =>
           [1 => Planned_Item,
            others => Empty_Occurrence],
         Comp_Count => 0,
         Comp_Items => [others => Empty_Completion],
         Ret_Count => 0,
         Ret_Items => [others => Empty_Retirement],
         Repl_Count => 0,
         Repl_Items => [others => Empty_Replacement]);

      Actual_Before : constant Semantic_Image :=
        (Snapshot => 10,
         Count    => 0,
         Events   => [others => Empty_Ev]);

      Scheduled_Middle : Scheduled_Lifecycle;
      Actual_Middle    : Semantic_Image;
      Scheduled_After  : Scheduled_Lifecycle;
      Actual_After     : Semantic_Image;
      Status           : Protocol_Status;
   begin
      Compose_Relation_First
        (Scheduled_Before,
         Actual_Before,
         Claim,
         Added_Actual,
         11,
         Scheduled_Middle,
         Actual_Middle,
         Scheduled_After,
         Actual_After,
         Status);

      Assert
        (Status = Protocol_Composed,
         "relation-first completion protocol composes");
      Assert
        (Relation_First_Completion
           (Scheduled_Before,
            Actual_Before,
            Claim,
            Added_Actual,
            11,
            Scheduled_Middle,
            Actual_Middle,
            Scheduled_After,
            Actual_After),
         "successful composition satisfies complete protocol relation");
      Assert
        (Inert_Middle (Scheduled_Middle, Actual_Middle, Claim),
         "middle retains claim while Actual endpoint is absent");
      Assert
        (Effective_Finish
           (Scheduled_After, Actual_After, Claim, Added_Actual),
         "finish selects exact completion Actual while preserving claim");
      Assert
        (Actual_Middle = Actual_Before,
         "relation-first middle does not expose the Actual Event");
      Assert
        (Scheduled_After = Scheduled_Middle,
         "Actual publication does not rewrite Scheduled authority");
      Assert
        (Reference_Lookup (Actual_After, Claim.Actual).State = Found,
         "completion endpoint becomes visible only in finish");
      if Reference_Lookup (Actual_After, Claim.Actual).State = Found then
         Assert
           (Reference_Lookup (Actual_After, Claim.Actual).Value = Added_Actual,
            "visible endpoint is the exact complete Actual Event");
      end if;

      declare
         Wrong_Claim : Completion_Record := Claim;
      begin
         Wrong_Claim.Actual :=
           (Token => Make_Token ("scheduled-completion:other"));
         Compose_Relation_First
           (Scheduled_Before,
            Actual_Before,
            Wrong_Claim,
            Added_Actual,
            11,
            Scheduled_Middle,
            Actual_Middle,
            Scheduled_After,
            Actual_After,
            Status);
         Assert
           (Status = Endpoint_Mismatch,
            "claim/Event identity mismatch is rejected before transition");
      end;

      declare
         Full_Actual : Semantic_Image := Actual_Before;
      begin
         Full_Actual.Count := Max_Events;
         for I in 1 .. Max_Events loop
            declare
               Effects : Effect_List :=
                 (Count => 2, Values => [others => Empty_Effect]);
               Id_Text : constant String :=
                 "existing-" & Character'Val
                   (Character'Pos ('0') + I);
            begin
               Effects.Values (1) :=
                 (Key => No_Effect_Key,
                  Locus => (Token => Make_Token ("cash")),
                  Measure => (Token => Make_Token ("jpy")),
                  Amount => (Quanta => -1));
               Effects.Values (2) :=
                 (Key => No_Effect_Key,
                  Locus => (Token => Make_Token ("food")),
                  Measure => (Token => Make_Token ("jpy")),
                  Amount => (Quanta => 1));
               Full_Actual.Events (Event_Position (I)) :=
                 Make_Event ((Token => Make_Token (Id_Text)), Effects);
            end;
         end loop;

         Compose_Relation_First
           (Scheduled_Before,
            Full_Actual,
            Claim,
            Added_Actual,
            12,
            Scheduled_Middle,
            Actual_Middle,
            Scheduled_After,
            Actual_After,
            Status);
         Assert
           (Status = Actual_Preflight_Rejected,
            "Actual capacity rejection occurs before middle is exposed");
         Assert
           (Scheduled_Middle = Scheduled_Before,
            "failed Actual preflight leaves Scheduled output at before image");
      end;
   end Run;

end Test_Scheduled_Completion_Protocol;
