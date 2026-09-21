with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Event;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with Test_Support;        use Test_Support;

package body Test_Actual_Bounded_History is

   use type HRA_N.Core.Event.Effect_List;

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

      Empty : Semantic_Image :=
        (Snapshot => 1,
         Count    => 0,
         Events   => [others => Empty_Event]);
      Source : constant Semantic_Image :=
        (Snapshot => 7,
         Count    => 3,
         Events   => [1 => E1, 2 => E2, 3 => E3, others => Empty_Event]);
      Duplicate : constant Semantic_Image :=
        (Snapshot => 8,
         Count    => 2,
         Events   => [1 => E1, 2 => E1, others => Empty_Event]);
      Index  : Derived_Index;
      Status : Build_Status;
   begin
      Build_Index (Empty, Index, Status);
      Assert (Status = Index_Built, "empty image index builds");
      Assert (Index_Is_Qualified (Empty, Index), "empty index is qualified");
      Assert
        (Reference_Lookup (Empty, E_Id ("absent")).State = Not_Found,
         "empty reference lookup is not found");
      Assert
        (Derived_Lookup (Empty, Index, E_Id ("absent")).State = Not_Found,
         "empty derived lookup is not found");

      Empty.Count := 1;
      Empty.Events (1) := E1;
      Build_Index (Empty, Index, Status);
      Assert (Status = Index_Built, "one-event image index builds");
      Assert
        (Derived_Lookup (Empty, Index, E_Id ("e1")).State = Found,
         "one-event lookup finds its event");

      Build_Index (Source, Index, Status);
      Assert (Status = Index_Built, "multi-event image index builds");
      Assert (Index_Is_Qualified (Source, Index), "built index is qualified");

      for I in Event_Position range 1 .. 3 loop
         declare
            Key : constant Event_Id := HRA_N.Core.Event.Id (Source.Events (I));
            Reference : constant Lookup_Result := Reference_Lookup (Source, Key);
            Derived   : constant Lookup_Result := Derived_Lookup (Source, Index, Key);
         begin
            Assert (Reference.State = Found, "reference finds first/middle/last");
            Assert (Derived = Reference, "derived equals reference first/middle/last");
            if Derived.State = Found then
               Assert
                 (HRA_N.Core.Event.Effects (Derived.Value) =
                    HRA_N.Core.Event.Effects (Source.Events (I)),
                  "returned payload matches source");
            end if;
         end;
      end loop;

      Assert
        (Reference_Lookup (Source, E_Id ("absent")).State = Not_Found,
         "reference reports absent event");
      Assert
        (Derived_Lookup (Source, Index, E_Id ("absent")).State = Not_Found,
         "derived reports absent event");

      Build_Index (Duplicate, Index, Status);
      Assert
        (Status = Duplicate_Event_Id,
         "duplicate Event_Id is explicitly rejected");

      Build_Index (Source, Index, Status);
      Index.Count := 2;
      Assert
        (not Index_Is_Qualified (Source, Index),
         "missing binding is unqualified");
      Assert
        (Derived_Lookup (Source, Index, E_Id ("e1")).State = Invalid_Index,
         "missing binding cannot silently succeed");

      Build_Index (Source, Index, Status);
      Index.Bindings (2).Position := 8;
      Assert
        (not Index_Is_Qualified (Source, Index),
         "out-of-range locator is unqualified");
      Assert
        (Derived_Lookup (Source, Index, E_Id ("e2")).State = Invalid_Index,
         "out-of-range locator is rejected by lookup");

      Build_Index (Source, Index, Status);
      Index.Bindings (2).Key := E_Id ("wrong");
      Assert
        (not Index_Is_Qualified (Source, Index),
         "locator identity mismatch is unqualified");
      Assert
        (Derived_Lookup (Source, Index, E_Id ("e2")).State = Invalid_Index,
         "locator identity mismatch is rejected by lookup");

      Build_Index (Source, Index, Status);
      Index.Bindings (2).Position := Index.Bindings (1).Position;
      Assert
        (not Index_Is_Qualified (Source, Index),
         "duplicate locator alias is unqualified");
      Assert
        (Derived_Lookup (Source, Index, E_Id ("e2")).State = Invalid_Index,
         "duplicate locator alias is rejected by lookup");

      Build_Index (Source, Index, Status);
      Index.Snapshot := Source.Snapshot + 1;
      Assert
        (not Index_Is_Qualified (Source, Index),
         "snapshot mismatch is unqualified");
      Assert
        (Derived_Lookup (Source, Index, E_Id ("e1")).State = Invalid_Index,
         "snapshot mismatch is rejected by lookup");
   end Run;

end Test_Actual_Bounded_History;
