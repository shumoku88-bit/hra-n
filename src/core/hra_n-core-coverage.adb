-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Coverage
-------------------------------------------------------------------------------

package body HRA_N.Core.Coverage with
  SPARK_Mode => On
is

   function Make_Coverage (Coords : Coordinate_List) return Zero_Origin_Coverage is
   begin
      return (Coords => Coords);
   end Make_Coverage;

   function Is_Covered
     (Coverage : Zero_Origin_Coverage;
      Coord    : Coordinate_Type) return Boolean
   is
   begin
      for I in 1 .. Coverage.Coords.Count loop
         if Equal_Coordinate (Coverage.Coords.Values (I), Coord) then
            return True;
         end if;
      end loop;
      return False;
   end Is_Covered;

   function Inspect_Balance
     (Coverage     : Zero_Origin_Coverage;
      Coord        : Coordinate_Type;
      Total_Quanta : Long_Long_Integer) return Balance_Result
   is
   begin
      if Is_Covered (Coverage, Coord) then
         return (Status => Covered, Amount => Total_Quanta);
      else
         return (Status => Coverage_Missing);
      end if;
   end Inspect_Balance;

end HRA_N.Core.Coverage;
