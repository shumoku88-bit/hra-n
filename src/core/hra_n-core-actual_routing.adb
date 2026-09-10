-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Routing
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Routing with
  SPARK_Mode => On
is

   ----------------------------------------------------------------------------
   --  Find_Purpose
   ----------------------------------------------------------------------------
   procedure Find_Purpose
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      Purpose : out Token_Text;
      Found   : out Boolean)
   is
   begin
      Purpose := (Length => 0, Value => [others => ' ']);
      Found   := False;
      for I in 1 .. Map.Count loop
         if Equal_Token (Map.Entries (I).Locus.Token, Locus.Token) then
            Purpose := Map.Entries (I).Purpose;
            Found   := True;
            return;
         end if;
      end loop;
   end Find_Purpose;

   ----------------------------------------------------------------------------
   --  Is_Managed
   ----------------------------------------------------------------------------
   function Is_Managed
     (Map   : Routing_Map;
      Locus : Locus_Id) return Boolean
   is
      Dummy_Purp : Token_Text;
      Found      : Boolean;
   begin
      Find_Purpose (Map, Locus, Dummy_Purp, Found);
      return Found;
   end Is_Managed;

   ----------------------------------------------------------------------------
   --  Purpose_Matches
   ----------------------------------------------------------------------------
   function Purpose_Matches
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      Purpose : Token_Text) return Boolean
   is
      Found_Purp : Token_Text;
      Found      : Boolean;
   begin
      Find_Purpose (Map, Locus, Found_Purp, Found);
      if Found then
         return Equal_Token (Found_Purp, Purpose);
      end if;
      return False;
   end Purpose_Matches;

end HRA_N.Core.Actual_Routing;
