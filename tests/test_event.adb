with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;
with HRA_N.Core.Event;    use HRA_N.Core.Event;
with Test_Support;        use Test_Support;

package body Test_Event is

   procedure Run is
      Ev_Id : constant Event_Id  := (Token => Make_Token ("e0001"));
      JPY   : constant Measure_Id := (Token => Make_Token ("jpy"));
      USD   : constant Measure_Id := (Token => Make_Token ("usd"));
      Bank  : constant Locus_Id   := (Token => Make_Token ("bank"));
      Food  : constant Locus_Id   := (Token => Make_Token ("food"));

      K1 : constant Effect_Key := (Token => Make_Token ("k1"));
      K2 : constant Effect_Key := (Token => Make_Token ("k2"));

      Unique_Effects    : Effect_List;
      Duplicate_Effects : Effect_List;
      Multi_Measure     : Effect_List;
   begin
      -- Test 1: Unique effect keys
      Unique_Effects.Count := 2;
      Unique_Effects.Values (1) := (Key => K1, Locus => Bank, Measure => JPY, Amount => Of_Quanta (-200));
      Unique_Effects.Values (2) := (Key => K2, Locus => Food, Measure => JPY, Amount => Of_Quanta (200));
      Assert (Keys_Are_Unique (Unique_Effects), "Keys_Are_Unique accepts distinct keys");

      -- Test 2: Duplicate effect keys rejected
      Duplicate_Effects.Count := 2;
      Duplicate_Effects.Values (1) := (Key => K1, Locus => Bank, Measure => JPY, Amount => Of_Quanta (-200));
      Duplicate_Effects.Values (2) := (Key => K1, Locus => Food, Measure => JPY, Amount => Of_Quanta (200));
      Assert (not Keys_Are_Unique (Duplicate_Effects), "Keys_Are_Unique rejects duplicate keys");

      -- Test 3: Event construction and projection
      declare
         Ev : constant Event := Make_Event (Ev_Id, Unique_Effects);
      begin
         Assert_Equal_Int (2, Long_Long_Integer (Effect_Count (Ev)), "Event effect count is 2");
         Assert_Equal_Int (-200, Quantity_At (Ev, Bank, JPY), "Quantity at Bank is -200 JPY");
         Assert_Equal_Int (200, Quantity_At (Ev, Food, JPY), "Quantity at Food is +200 JPY");
         Assert_Equal_Int (0, Quantity_At (Ev, Bank, USD), "Quantity at Bank for USD is 0");

         Assert (Is_Balanced_Single_Measure (Ev, JPY), "Single-measure JPY closes to zero");
         Assert (not Is_Balanced_Single_Measure (Ev, USD), "USD check fails when no USD effects");
      end;

      -- Test 4: Multi-measure event is rejected by Is_Balanced_Single_Measure
      Multi_Measure.Count := 2;
      Multi_Measure.Values (1) := (Key => K1, Locus => Bank, Measure => JPY, Amount => Of_Quanta (-200));
      Multi_Measure.Values (2) := (Key => K2, Locus => Food, Measure => USD, Amount => Of_Quanta (200));
      declare
         Ev_Multi : constant Event := Make_Event (Ev_Id, Multi_Measure);
      begin
         Assert (not Is_Balanced_Single_Measure (Ev_Multi, JPY),
                 "Multi-measure event rejected by Is_Balanced_Single_Measure");
      end;
   end Run;

end Test_Event;
