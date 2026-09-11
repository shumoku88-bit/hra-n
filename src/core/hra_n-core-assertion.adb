-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Assertion
-------------------------------------------------------------------------------

package body HRA_N.Core.Assertion with
  SPARK_Mode => Off
is

   function Date_Less_Or_Equal (Left, Right : Date_Type) return Boolean is
   begin
      if Left.Year /= Right.Year then
         return Left.Year < Right.Year;
      elsif Left.Month /= Right.Month then
         return Left.Month < Right.Month;
      else
         return Left.Day <= Right.Day;
      end if;
   end Date_Less_Or_Equal;

   procedure Add_Assertion
     (Memory  : in out Assertion_Memory;
      Item    : Balance_Assertion;
      Success : out Boolean)
   is
   begin
      Success := False;
      if Memory.Count = Max_Assertions then
         return;
      end if;

      for I in 1 .. Memory.Count loop
         if Equal_Token (Memory.Values (I).Id.Token, Item.Id.Token) then
            return;
         end if;
      end loop;

      Memory.Count := Memory.Count + 1;
      Memory.Values (Memory.Count) := Item;
      Success := True;
   end Add_Assertion;

   procedure Find_Assertion
     (Memory : Assertion_Memory;
      Id     : Assertion_Id;
      Item   : out Balance_Assertion;
      Found  : out Boolean)
   is
   begin
      Found := False;
      Item := Empty_Assertion;
      for I in 1 .. Memory.Count loop
         if Equal_Token (Memory.Values (I).Id.Token, Id.Token) then
            Item := Memory.Values (I);
            Found := True;
            return;
         end if;
      end loop;
   end Find_Assertion;

   procedure Find_Latest_Assertion
     (Memory : Assertion_Memory;
      Coord  : Coordinate_Type;
      As_Of  : Date_Type;
      Item   : out Balance_Assertion;
      Found  : out Boolean)
   is
      Best_Idx : Natural := 0;
   begin
      Found := False;
      Item := Empty_Assertion;

      for I in 1 .. Memory.Count loop
         if Equal_Coordinate (Memory.Values (I).Coordinate, Coord)
           and then Date_Less_Or_Equal (Memory.Values (I).Valid_On, As_Of)
         then
            if Best_Idx = 0
              or else Date_Less_Or_Equal (Memory.Values (Best_Idx).Valid_On,
                                          Memory.Values (I).Valid_On)
            then
               Best_Idx := I;
            end if;
         end if;
      end loop;

      if Best_Idx > 0 then
         Item := Memory.Values (Best_Idx);
         Found := True;
      end if;
   end Find_Latest_Assertion;

end HRA_N.Core.Assertion;
