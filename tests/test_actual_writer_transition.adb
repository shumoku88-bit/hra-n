with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Writer_Transition;
use HRA_N.Core.Actual_Writer_Transition;
with HRA_N.Core.Event;    use HRA_N.Core.Event;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with Test_Support;        use Test_Support;

package body Test_Actual_Writer_Transition is

   function E_Id (Text : String) return Event_Id is
     ((Token => Make_Token (Text)));

   function Make_Test_Event
     (Name   : String;
      Amount : Quanta_Type) return Event
   is
      Items : Effect_List;
   begin
      Items.Count := 1;
      Items.Values (1) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("proof")),
         Measure => (Token => Make_Token ("unit")),
         Amount  => Of_Quanta (Amount));
      return Make_Event (E_Id (Name), Items);
   end Make_Test_Event;

   procedure Run is
      Empty : constant Event := Make_Test_Event ("empty", 0);
      E1    : constant Event := Make_Test_Event ("record-1", 10);
      E2    : constant Event := Make_Test_Event ("record-2", 20);
      E3    : constant Event := Make_Test_Event ("record-3", 30);
      Source : constant Semantic_Image :=
        (Snapshot => 100,
         Count    => 2,
         Events   => [1 => E1, 2 => E2, others => Empty]);
      Target : Semantic_Image;
      Status : Transition_Status;
   begin
      Append_Fresh (Source, E3, 101, Target, Status);

      Assert (Status = Transitioned, "fresh Event transition succeeds");
      Assert
        (One_Fresh_Append (Source, E3, 101, Target),
         "successful transition establishes one-fresh-append relation");
      Assert
        (Target.Snapshot = 101,
         "target preserves caller-supplied generation token");
      Assert
        (Target.Count = Source.Count + 1,
         "transition adds exactly one Event");
      Assert
        (Target.Events (1) = E1
         and then Target.Events (2) = E2,
         "transition preserves complete prior Event prefix");
      Assert
        (Target.Events (3) = E3,
         "transition retains complete added Event");
      Assert
        (Event_Ids_Are_Unique (Target),
         "fresh append preserves Event identity uniqueness");

      declare
         Added : constant Lookup_Result :=
           Reference_Lookup (Target, E_Id ("record-3"));
         Prior : constant Lookup_Result :=
           Reference_Lookup (Target, E_Id ("record-1"));
      begin
         Assert
           (Added.State = Found
            and then Added.Position = 3
            and then Added.Value = E3,
            "added Event is visible through bounded reference lookup");
         Assert
           (Prior = Reference_Lookup (Source, E_Id ("record-1")),
            "prior lookup meaning is unchanged");
      end;

      Append_Fresh (Source, E2, 102, Target, Status);
      Assert
        (Status = Duplicate_Event_Id,
         "duplicate Event identity fails closed");

      declare
         Full : constant Semantic_Image :=
           (Snapshot => 200,
            Count    => Max_Events,
            Events   =>
              [1 => Make_Test_Event ("f1", 1),
               2 => Make_Test_Event ("f2", 2),
               3 => Make_Test_Event ("f3", 3),
               4 => Make_Test_Event ("f4", 4),
               5 => Make_Test_Event ("f5", 5),
               6 => Make_Test_Event ("f6", 6),
               7 => Make_Test_Event ("f7", 7),
               8 => Make_Test_Event ("f8", 8)]);
      begin
         Append_Fresh
           (Full, Make_Test_Event ("f9", 9), 201, Target, Status);
         Assert
           (Status = Source_Full,
            "bounded proof model refuses overflow without prefix acceptance");
      end;

      declare
         Duplicate_Source : constant Semantic_Image :=
           (Snapshot => 300,
            Count    => 2,
            Events   => [1 => E1, 2 => E1, others => Empty]);
      begin
         Append_Fresh
           (Duplicate_Source, E3, 301, Target, Status);
         Assert
           (Status = Source_Not_Unique,
            "non-admitted source image cannot transition");
      end;
   end Run;

end Test_Actual_Writer_Transition;
