-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Relation
-------------------------------------------------------------------------------

package body HRA_N.Core.Relation with
  SPARK_Mode => On
is

   procedure Find_Unit
     (Mem   : Unit_Memory;
      Id    : Token_Text;
      Value : out Relation_Unit;
      Found : out Boolean)
   is
   begin
      Value := Empty_Unit;
      Found := False;
      for I in 1 .. Mem.Count loop
         if Equal_Token (Mem.Units (I).Id, Id) then
            Value := Mem.Units (I);
            Found := True;
            return;
         end if;
      end loop;
   end Find_Unit;

end HRA_N.Core.Relation;
