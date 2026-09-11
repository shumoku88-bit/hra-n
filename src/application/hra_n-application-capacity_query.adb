-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Capacity_Query
-------------------------------------------------------------------------------

with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Capacity_Query is

   function Execute (Paths : Path_Config) return Capacity_View is
      View   : Capacity_View;
      Policy : Policy_Result;
      JPY    : constant Token_Text := Make_Token ("jpy");

      procedure Set_Error (Message : String) is
         Len : constant Natural := Natural'Min (Message'Length, View.Error'Length);
      begin
         View.Success := False;
         View.Error_Len := Len;
         View.Error (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
      end Set_Error;

      procedure Add_Row (Coord : Capacity_Coordinate) is
      begin
         for I in 1 .. View.Count loop
            if Equal_Coordinate (View.Rows (I).Coord, Coord) then
               return;
            end if;
         end loop;
         if View.Count < Max_Query_Rows then
            View.Count := View.Count + 1;
            View.Rows (View.Count) :=
              (Coord  => Coord,
               Amount => Entitlement_At (Policy.Capacities, Coord, JPY));
         end if;
      end Add_Row;
   begin
      if not Paths.Resolution_Ok then
         Set_Error ("authority resolution failed");
         return View;
      end if;

      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Policy.Success then
         Set_Error ("cannot query an unadmitted authority snapshot");
         return View;
      end if;

      Add_Row (Make_Unallocated_Coordinate);
      for I in 1 .. Policy.Capacities.Movement_Count loop
         for C in 1 .. Policy.Capacities.Movements (I).Change_Count loop
            if Policy.Capacities.Movements (I).Changes (C).Coord.Kind = Coord_Purpose then
               Add_Row (Policy.Capacities.Movements (I).Changes (C).Coord);
            end if;
         end loop;
      end loop;

      View.Complete := Effective_Evidence_Complete (Policy.Capacities);
      View.Success := True;
      return View;
   end Execute;

end HRA_N.Application.Capacity_Query;
