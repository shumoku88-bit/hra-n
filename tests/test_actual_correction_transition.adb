with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Correction_Transition;
use HRA_N.Core.Actual_Correction_Transition;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with Test_Support; use Test_Support;

package body Test_Actual_Correction_Transition is

   function E_Id (Text : String) return Event_Id is
     ((Token => Make_Token (Text)));

   function Make_Test_Event
     (Name   : String;
      Amount : Quanta_Type) return HRA_N.Core.Event.Event
   is
      Items : Effect_List;
   begin
      Items.Count := 2;
      Items.Values (1) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("left")),
         Measure => (Token => Make_Token ("unit")),
         Amount  => Of_Quanta (-Amount));
      Items.Values (2) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("right")),
         Measure => (Token => Make_Token ("unit")),
         Amount  => Of_Quanta (Amount));
      return Make_Event (E_Id (Name), Items);
   end Make_Test_Event;

   procedure Run is
      Empty : constant HRA_N.Core.Event.Event :=
        Make_Test_Event ("empty", 1);
      Original : constant HRA_N.Core.Event.Event :=
        Make_Test_Event ("record-1", 10);
      First_Replacement : constant HRA_N.Core.Event.Event :=
        Make_Test_Event ("replacement-1", 15);
      Next_Replacement : constant HRA_N.Core.Event.Event :=
        Make_Test_Event ("replacement-2", 20);
      Source : constant Correction_Image :=
        (Events =>
           (Snapshot => 700,
            Count    => 2,
            Events   =>
              [1 => Original,
               2 => First_Replacement,
               others => Empty]),
         Edge_Count => 1,
         Edges =>
           [1 =>
              (Target      => E_Id ("record-1"),
               Replacement => E_Id ("replacement-1")),
            others => Empty_Edge]);
      Target : Correction_Image;
      Status : Correction_Transition_Status;
   begin
      Assert
        (Correction_Shape_Admitted (Source),
         "source correction image admits local shape");
      Assert
        (not Current_In_Frontier (Source, E_Id ("record-1"))
         and then
           Current_In_Frontier (Source, E_Id ("replacement-1")),
         "source frontier exposes terminal replacement");

      Append_Current_Correction
        (Source,
         E_Id ("replacement-1"),
         Next_Replacement,
         701,
         Target,
         Status);

      Assert
        (Status = Correction_Transitioned,
         "current correction target accepts fresh replacement");
      Assert
        (One_Current_Correction
           (Source,
            E_Id ("replacement-1"),
            Next_Replacement,
            701,
            Target),
         "successful transition establishes correction relation");
      Assert
        (Target.Events.Count = 3
         and then Target.Edge_Count = 2,
         "correction adds exactly one Event and one edge");
      Assert
        (Target.Events.Events (1) = Original
         and then Target.Events.Events (2) = First_Replacement,
         "correction preserves complete retained Event history");
      Assert
        (Target.Edges (1) = Source.Edges (1),
         "correction preserves prior replacement evidence");
      Assert
        (not Current_In_Frontier (Target, E_Id ("replacement-1"))
         and then Current_In_Frontier (Target, E_Id ("replacement-2")),
         "frontier moves from target to fresh replacement");

      Append_Current_Correction
        (Source,
         E_Id ("record-1"),
         Next_Replacement,
         702,
         Target,
         Status);
      Assert
        (Status = Target_Not_Current,
         "superseded target cannot receive a sibling correction");

      Append_Current_Correction
        (Source,
         E_Id ("replacement-1"),
         First_Replacement,
         703,
         Target,
         Status);
      Assert
        (Status = Duplicate_Replacement_Id,
         "replacement identity must be fresh");
   end Run;

end Test_Actual_Correction_Transition;
