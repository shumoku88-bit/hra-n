with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Correction_Transition;
use HRA_N.Core.Actual_Correction_Transition;
with HRA_N.Core.Actual_Reversal_Transition;
use HRA_N.Core.Actual_Reversal_Transition;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with Test_Support; use Test_Support;

package body Test_Actual_Reversal_Transition is

   function E_Id (Text : String) return Event_Id is
     ((Token => Make_Token (Text)));

   function Make_Movement
     (Name   : String;
      Amount : Quanta_Type) return HRA_N.Core.Event.Event
   is
      Items : Effect_List;
   begin
      Items.Count := 2;
      Items.Values (1) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("left")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => Of_Quanta (-Amount));
      Items.Values (2) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("right")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => Of_Quanta (Amount));
      return Make_Event (E_Id (Name), Items);
   end Make_Movement;

   function Make_Inverse
     (Target_Name : String;
      Amount      : Quanta_Type) return HRA_N.Core.Event.Event is
     (Make_Movement ("actual-reversal:" & Target_Name, -Amount));

   procedure Run is
      Empty : constant HRA_N.Core.Event.Event :=
        Make_Movement ("empty", 1);
      Old : constant HRA_N.Core.Event.Event :=
        Make_Movement ("record-old", 10);
      Current : constant HRA_N.Core.Event.Event :=
        Make_Movement ("record-1", 15);
      Prior_Target : constant HRA_N.Core.Event.Event :=
        Make_Movement ("record-2", 7);
      Prior_Reversal : constant HRA_N.Core.Event.Event :=
        Make_Inverse ("record-2", 7);
      New_Reversal : constant HRA_N.Core.Event.Event :=
        Make_Inverse ("record-1", 15);
      Source : constant Reversal_Image :=
        (Corrections =>
           (Events =>
              (Snapshot => 900,
               Count    => 4,
               Events   =>
                 [1 => Old,
                  2 => Current,
                  3 => Prior_Target,
                  4 => Prior_Reversal,
                  others => Empty]),
            Edge_Count => 1,
            Edges =>
              [1 =>
                 (Target      => E_Id ("record-old"),
                  Replacement => E_Id ("record-1")),
               others =>
                 (Target      => E_Id ("unused-target"),
                  Replacement => E_Id ("unused-replacement"))]),
         Edge_Count => 1,
         Edges =>
           [1 =>
              (Target   => E_Id ("record-2"),
               Reversal => E_Id ("actual-reversal:record-2")),
            others =>
              (Target   => E_Id ("unused-target"),
               Reversal => E_Id ("unused-reversal"))]);
      Result : Reversal_Image;
      Status : Reversal_Transition_Status;
   begin
      Assert
        (Reversal_Shape_Admitted (Source),
         "source reversal image admits correction and reversal topology");
      Assert
        (Current_In_Frontier (Source.Corrections, E_Id ("record-1")),
         "selected target is current in correction frontier");
      Assert
        (not Is_Reversal_Endpoint (Source, E_Id ("record-1")),
         "selected target has no prior reversal role");
      Assert
        (Writer_Inverse_Of (Current, New_Reversal),
         "new Event is the writer-specific exact inverse");
      Assert
        (Same_Id
           (Id (New_Reversal),
            Deterministic_Reversal_Id (E_Id ("record-1"))),
         "reversal identity is deterministic");

      Append_Current_Reversal
        (Source,
         E_Id ("record-1"),
         Current,
         New_Reversal,
         901,
         Result,
         Status);

      Assert
        (Status = Reversal_Transitioned,
         "current target accepts deterministic exact inverse");
      Assert
        (One_Current_Reversal
           (Source,
            E_Id ("record-1"),
            Current,
            New_Reversal,
            901,
            Result),
         "successful transition establishes full reversal relation");
      Assert
        (Result.Corrections.Events.Count = 5
         and then Result.Corrections.Edge_Count = 1
         and then Result.Edge_Count = 2,
         "reversal appends one Event and one reversal edge only");
      Assert
        (Result.Corrections.Events.Events (1) = Old
         and then Result.Corrections.Events.Events (2) = Current
         and then Result.Corrections.Events.Events (3) = Prior_Target
         and then Result.Corrections.Events.Events (4) = Prior_Reversal,
         "all retained prior Events remain exact");
      Assert
        (Result.Corrections.Edges (1) = Source.Corrections.Edges (1),
         "correction evidence is preserved unchanged");
      Assert
        (Result.Edges (1) = Source.Edges (1),
         "prior reversal evidence is preserved unchanged");
      Assert
        (Same_Id (Result.Edges (2).Target, E_Id ("record-1"))
         and then
           Same_Id
             (Result.Edges (2).Reversal,
              E_Id ("actual-reversal:record-1")),
         "new reversal edge records exact provenance");
      Assert
        (Current_In_Frontier (Result.Corrections, E_Id ("record-1")),
         "reversal does not supersede or move correction frontier");
      Assert
        (Reversal_Shape_Admitted (Result),
         "successful result remains admitted for later reversals");

      Append_Current_Reversal
        (Source,
         E_Id ("record-old"),
         Old,
         Make_Inverse ("record-old", 10),
         902,
         Result,
         Status);
      Assert
        (Status = Target_Not_Current,
         "superseded correction target cannot be reversed");

      Append_Current_Reversal
        (Source,
         E_Id ("record-2"),
         Prior_Target,
         Make_Inverse ("record-2", 7),
         903,
         Result,
         Status);
      Assert
        (Status = Target_Already_In_Reversal,
         "existing reversal endpoint cannot be reversed again");

      Append_Current_Reversal
        (Source,
         E_Id ("record-1"),
         Prior_Target,
         New_Reversal,
         904,
         Result,
         Status);
      Assert
        (Status = Target_Event_Mismatch,
         "caller-supplied target Event must match retained source payload");

      declare
         Wrong_Id : constant HRA_N.Core.Event.Event :=
           Make_Movement ("wrong-reversal-id", -15);
      begin
         Append_Current_Reversal
           (Source,
            E_Id ("record-1"),
            Current,
            Wrong_Id,
            905,
            Result,
            Status);
         Assert
           (Status = Wrong_Reversal_Id,
            "candidate identity must be deterministic");
      end;

      declare
         Wrong_Amount : constant HRA_N.Core.Event.Event :=
           Make_Inverse ("record-1", 14);
      begin
         Append_Current_Reversal
           (Source,
            E_Id ("record-1"),
            Current,
            Wrong_Amount,
            906,
            Result,
            Status);
         Assert
           (Status = Reversal_Not_Exact_Inverse,
            "candidate Effects must be the exact writer inverse");
      end;
   end Run;

end Test_Actual_Reversal_Transition;
