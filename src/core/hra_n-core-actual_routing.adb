-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Routing
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Routing with
  SPARK_Mode => On
is

   function Same_Coordinate (Left, Right : Routing_Entry) return Boolean is
     (Equal_Token (Left.Locus.Token, Right.Locus.Token)
      and then Left.Effective_Kind = Right.Effective_Kind
      and then (Left.Effective_Kind = Routing_Initial
                or else Equal_Date (Left.Effective_On, Right.Effective_On)));

   function Coordinates_Are_Unique (Map : Routing_Map) return Boolean is
   begin
      for I in 1 .. Map.Count loop
         for J in I + 1 .. Map.Count loop
            if Same_Coordinate (Map.Entries (I), Map.Entries (J)) then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Coordinates_Are_Unique;

   procedure Find_Purpose_As_Of
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      As_Of   : Date_Type;
      Purpose : out Token_Text;
      Found   : out Boolean)
   is
      Has_Choice : Boolean := False;
      Choice     : Routing_Entry := Empty_Routing_Entry;
   begin
      Purpose := (Length => 0, Value => [others => ' ']);
      Found := False;
      for I in 1 .. Map.Count loop
         declare
            Item       : Routing_Entry renames Map.Entries (I);
            Applicable : constant Boolean :=
              Item.Effective_Kind = Routing_Initial
              or else Date_Less (Item.Effective_On, As_Of)
              or else Equal_Date (Item.Effective_On, As_Of);
            Later      : constant Boolean :=
              not Has_Choice
              or else (Choice.Effective_Kind = Routing_Initial
                       and then Item.Effective_Kind = Routing_From_Date)
              or else (Choice.Effective_Kind = Routing_From_Date
                       and then Item.Effective_Kind = Routing_From_Date
                       and then Date_Less (Choice.Effective_On, Item.Effective_On));
         begin
            if Applicable
              and then Equal_Token (Item.Locus.Token, Locus.Token)
              and then Later
            then
               Choice := Item;
               Has_Choice := True;
            end if;
         end;
      end loop;
      if Has_Choice and then Choice.Managed then
         Purpose := Choice.Purpose;
         Found := True;
      end if;
   end Find_Purpose_As_Of;

   procedure Find_Purpose
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      Purpose : out Token_Text;
      Found   : out Boolean)
   is
      Has_Choice : Boolean := False;
      Choice     : Routing_Entry := Empty_Routing_Entry;
   begin
      Purpose := (Length => 0, Value => [others => ' ']);
      Found := False;
      for I in 1 .. Map.Count loop
         declare
            Item  : Routing_Entry renames Map.Entries (I);
            Later : constant Boolean :=
              not Has_Choice
              or else (Choice.Effective_Kind = Routing_Initial
                       and then Item.Effective_Kind = Routing_From_Date)
              or else (Choice.Effective_Kind = Routing_From_Date
                       and then Item.Effective_Kind = Routing_From_Date
                       and then Date_Less (Choice.Effective_On, Item.Effective_On));
         begin
            if Equal_Token (Item.Locus.Token, Locus.Token) and then Later then
               Choice := Item;
               Has_Choice := True;
            end if;
         end;
      end loop;
      if Has_Choice and then Choice.Managed then
         Purpose := Choice.Purpose;
         Found := True;
      end if;
   end Find_Purpose;

   function Is_Managed
     (Map   : Routing_Map;
      Locus : Locus_Id) return Boolean
   is
      Dummy : Token_Text;
      Found : Boolean;
   begin
      Find_Purpose (Map, Locus, Dummy, Found);
      return Found;
   end Is_Managed;

   function Purpose_Matches
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      Purpose : Token_Text) return Boolean
   is
      Routed : Token_Text;
      Found  : Boolean;
   begin
      Find_Purpose (Map, Locus, Routed, Found);
      return Found and then Equal_Token (Routed, Purpose);
   end Purpose_Matches;

end HRA_N.Core.Actual_Routing;
