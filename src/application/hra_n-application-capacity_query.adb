-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Capacity_Query
-------------------------------------------------------------------------------

with Ada.Directories;
with HRA_N.Application.Canonical_Authority;
with HRA_N.Storage.Loam_Capacity_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Capacity_Query is

   function Execute (Paths : Path_Config) return Capacity_View is
      View : Capacity_View;
      JPY  : constant Token_Text := Make_Token ("jpy");

      procedure Set_Error (Message : String) is
         Len : constant Natural := Natural'Min (Message'Length, View.Error'Length);
      begin
         View.Success := False;
         View.Error_Len := Len;
         View.Error (1 .. Len) := Message (Message'First .. Message'First + Len - 1);
      end Set_Error;

      procedure Build_From_Capacities (Capacities : Capacity_Memory) is
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
                  Amount => Entitlement_At (Capacities, Coord, JPY));
            end if;
         end Add_Row;
      begin
         Add_Row (Make_Unallocated_Coordinate);
         for I in 1 .. Capacities.Movement_Count loop
            for C in 1 .. Capacities.Movements (I).Change_Count loop
               if Capacities.Movements (I).Changes (C).Coord.Kind = Coord_Purpose then
                  Add_Row (Capacities.Movements (I).Changes (C).Coord);
               end if;
            end loop;
         end loop;

         View.Complete := Effective_Evidence_Complete (Capacities);
         View.Success := True;
      end Build_From_Capacities;
   begin
      if not Paths.Resolution_Ok then
         Set_Error ("authority resolution failed");
         return View;
      elsif Paths.Is_Versioned then
         View.Snapshot :=
           (Kind     => HRA_N.Application.Frontend_Types.Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      declare
         use HRA_N.Application.Canonical_Authority;
         Root      : constant String := Data_Dir_Str (Paths);
         Authority : constant Authority_Probe := Probe (Root);
      begin
         case Authority.State is
            when Canonical_Present =>
               declare
                  C_Res : constant HRA_N.Storage.Loam_Capacity_Reader.Read_Result :=
                    HRA_N.Storage.Loam_Capacity_Reader.Read_File
                      (Ada.Directories.Compose (Root, "capacity.loam"));
               begin
                  if not C_Res.Success then
                     Set_Error ("capacity.loam: " & C_Res.Error_Reason (1 .. C_Res.Error_Len));
                     return View;
                  end if;

                  Build_From_Capacities (C_Res.Capacity);
                  return View;
               end;

            when Legacy_Only =>
               declare
                  Policy : constant Policy_Result :=
                    Read_Policy_File (Policy_Path_Str (Paths));
               begin
                  if not Policy.Success then
                     Set_Error ("cannot query an unadmitted authority snapshot");
                     return View;
                  end if;

                  Build_From_Capacities (Policy.Capacities);
                  return View;
               end;

            when Probe_Failed =>
               Set_Error (Authority.Diagnostic (1 .. Authority.Diagnostic_Len));
               return View;
         end case;
      end;
   end Execute;

end HRA_N.Application.Capacity_Query;
