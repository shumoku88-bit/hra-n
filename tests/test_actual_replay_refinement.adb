with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Replay_Refinement;
use HRA_N.Core.Actual_Replay_Refinement;
with HRA_N.Core.Event;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with Test_Support;        use Test_Support;

package body Test_Actual_Replay_Refinement is

   use type HRA_N.Core.Event.Event;

   function E_Id (Text : String) return Event_Id is
     ((Token => Make_Token (Text)));

   function Make_Test_Event
     (Name   : String;
      Amount : Quanta_Type) return HRA_N.Core.Event.Event
   is
      Effects : HRA_N.Core.Event.Effect_List;
   begin
      Effects.Count := 1;
      Effects.Values (1) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("test")),
         Measure => (Token => Make_Token ("unit")),
         Amount  => Of_Quanta (Amount));
      return HRA_N.Core.Event.Make_Event (E_Id (Name), Effects);
   end Make_Test_Event;

   procedure Run is
      Empty_Event : constant HRA_N.Core.Event.Event :=
        Make_Test_Event ("empty", 0);
      E1 : constant HRA_N.Core.Event.Event := Make_Test_Event ("e1", 10);
      E2 : constant HRA_N.Core.Event.Event := Make_Test_Event ("e2", 20);
      E3 : constant HRA_N.Core.Event.Event := Make_Test_Event ("e3", 30);

      Source : constant Semantic_Image :=
        (Snapshot => 13,
         Count    => 3,
         Events   => [1 => E1, 2 => E2, 3 => E3, others => Empty_Event]);

      --  Replay slots are deliberately permuted relative to canonical source
      --  order: e3, e1, e2.
      Base_Replay : constant Replay_View :=
        (Snapshot => 13,
         Count    => 3,
         Slots    => [1 => E3, 2 => E1, 3 => E2, others => Empty_Event]);

      Base_Index : constant Replay_Index :=
        (Snapshot => 13,
         Count    => 3,
         Bindings =>
           [1 => (Key => E_Id ("e1"), Locator => 2),
            2 => (Key => E_Id ("e2"), Locator => 3),
            3 => (Key => E_Id ("e3"), Locator => 1),
            others => (Key => E_Id ("empty"), Locator => 0)]);

      Replay : Replay_View;
      Index  : Replay_Index;
   begin
      Assert
        (Replay_Index_Is_Qualified (Source, Base_Replay, Base_Index),
         "permuted replay locators are qualified");

      for I in Event_Position range 1 .. 3 loop
         declare
            Key : constant Event_Id := HRA_N.Core.Event.Id (Source.Events (I));
            Reference : constant Lookup_Result := Reference_Lookup (Source, Key);
            Replayed  : constant Lookup_Result :=
              Replay_Lookup (Source, Base_Replay, Base_Index, Key);
         begin
            Assert (Reference.State = Found, "reference finds replayed event");
            Assert
              (Replayed = Reference,
               "qualified replay equals reference for first/middle/last");
         end;
      end loop;

      Assert
        (Replay_Lookup
           (Source, Base_Replay, Base_Index, E_Id ("absent")).State =
           Not_Found,
         "qualified replay preserves not-found meaning");

      Replay := Base_Replay;
      Replay.Snapshot := Source.Snapshot + 1;
      Assert
        (not Replay_Index_Is_Qualified (Source, Replay, Base_Index),
         "snapshot mismatch is unqualified");
      Assert
        (Replay_Lookup
           (Source, Replay, Base_Index, E_Id ("e1")).State = Invalid_Index,
         "snapshot mismatch fails closed");

      Replay := Base_Replay;
      Replay.Slots (2) := E3;
      Assert
        (not Replay_Index_Is_Qualified (Source, Replay, Base_Index),
         "payload mismatch is unqualified");
      Assert
        (Replay_Lookup
           (Source, Replay, Base_Index, E_Id ("e1")).State = Invalid_Index,
         "payload mismatch fails closed");

      Index := Base_Index;
      Index.Bindings (1).Key := E_Id ("wrong");
      Assert
        (not Replay_Index_Is_Qualified (Source, Base_Replay, Index),
         "identity mismatch is unqualified");
      Assert
        (Replay_Lookup
           (Source, Base_Replay, Index, E_Id ("e1")).State = Invalid_Index,
         "identity mismatch fails closed");

      Index := Base_Index;
      Index.Bindings (1).Locator := 0;
      Assert
        (not Replay_Index_Is_Qualified (Source, Base_Replay, Index),
         "missing locator is unqualified");
      Assert
        (Replay_Lookup
           (Source, Base_Replay, Index, E_Id ("e1")).State = Invalid_Index,
         "missing locator fails closed");

      Index := Base_Index;
      Index.Bindings (2).Locator := Index.Bindings (1).Locator;
      Assert
        (not Replay_Index_Is_Qualified (Source, Base_Replay, Index),
         "locator alias is unqualified");
      Assert
        (Replay_Lookup
           (Source, Base_Replay, Index, E_Id ("e2")).State = Invalid_Index,
         "locator alias fails closed");
   end Run;

end Test_Actual_Replay_Refinement;
