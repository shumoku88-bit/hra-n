-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Policy_Query
-------------------------------------------------------------------------------

with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Policy_Query is

   function Execute_Role_Query
     (Paths     : Path_Config;
      As_Of     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Has_As_Of : Boolean := False) return Role_View
   is
      Snap     : constant String := Snapshot_Id_Str (Paths);
      Snap_Len : constant Natural := Natural'Min (Snap'Length, 64);
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         declare
            Res : Role_View (0);
         begin
            Res.Status := Query_Rejected;
            Res.Diagnostic (1 .. 32) := "Unresolvable snapshot authority ";
            Res.Diagnostic_Len := 32;
            return Res;
         end;
      end if;

      declare
         P_Res : constant Policy_Result :=
           Read_Policy_File (Policy_Path_Str (Paths));
      begin
         if not P_Res.Success then
            declare
               Res : Role_View (0);
               L   : constant Natural :=
                 Natural'Min (P_Res.Error_Len, Res.Diagnostic'Length);
            begin
               Res.Status := Query_Rejected;
               Res.Diagnostic_Len := L;
               if L > 0 then
                  Res.Diagnostic (1 .. L) := P_Res.Error_Reason (1 .. L);
               end if;
               return Res;
            end;
         end if;

         declare
            Total_Active : constant Natural := Active_Count (P_Res.Roles);
            Res          : Role_View (Total_Active);
         begin
            Res.Snapshot_Len := Snap_Len;
            Res.Snapshot (1 .. Snap_Len) := Snap (Snap'First .. Snap'First + Snap_Len - 1);
            Res.Has_As_Of := Has_As_Of;
            Res.As_Of_Date := As_Of;
            Res.Status := Query_Complete;

            if Has_As_Of then
               for I in 1 .. Total_Active loop
                  declare
                     Active_Item : constant Role_Assignment := Active_Entry_At (P_Res.Roles, I);
                     Item_As_Of  : Role_Assignment;
                     Found       : Boolean := False;
                  begin
                     Find_Assignment_As_Of (P_Res.Roles, Active_Item.Locus, As_Of, Item_As_Of, Found);
                     if Found then
                        Res.Row_Count := Res.Row_Count + 1;
                        Res.Rows (Res.Row_Count) :=
                          (Id             => Item_As_Of.Id,
                           Locus          => Item_As_Of.Locus.Token,
                           Role           => Item_As_Of.Role,
                           Effective_From => Item_As_Of.Effective_From,
                           Has_Replaces   => Item_As_Of.Has_Replaces,
                           Replaces       => Item_As_Of.Replaces);
                     end if;
                  end;
               end loop;
            else
               for I in 1 .. Total_Active loop
                  declare
                     Active_Item : constant Role_Assignment := Active_Entry_At (P_Res.Roles, I);
                  begin
                     Res.Row_Count := Res.Row_Count + 1;
                     Res.Rows (Res.Row_Count) :=
                       (Id             => Active_Item.Id,
                        Locus          => Active_Item.Locus.Token,
                        Role           => Active_Item.Role,
                        Effective_From => Active_Item.Effective_From,
                        Has_Replaces   => Active_Item.Has_Replaces,
                        Replaces       => Active_Item.Replaces);
                  end;
               end loop;
            end if;

            --  Deterministic sort by Locus name
            for I in 1 .. Res.Row_Count loop
               for J in I + 1 .. Res.Row_Count loop
                  if Token_Less (Res.Rows (J).Locus, Res.Rows (I).Locus) then
                     declare
                        Tmp : constant Role_View_Row := Res.Rows (I);
                     begin
                        Res.Rows (I) := Res.Rows (J);
                        Res.Rows (J) := Tmp;
                     end;
                  end if;
               end loop;
            end loop;

            return Res;
         end;
      end;
   end Execute_Role_Query;

   function Execute_Window_Query
     (Paths : Path_Config) return Window_View
   is
      Snap     : constant String := Snapshot_Id_Str (Paths);
      Snap_Len : constant Natural := Natural'Min (Snap'Length, 64);
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         declare
            Res : Window_View (0);
         begin
            Res.Status := Query_Rejected;
            Res.Diagnostic (1 .. 32) := "Unresolvable snapshot authority ";
            Res.Diagnostic_Len := 32;
            return Res;
         end;
      end if;

      declare
         P_Res : constant Policy_Result :=
           Read_Policy_File (Policy_Path_Str (Paths));
      begin
         if not P_Res.Success then
            declare
               Res : Window_View (0);
               L   : constant Natural :=
                 Natural'Min (P_Res.Error_Len, Res.Diagnostic'Length);
            begin
               Res.Status := Query_Rejected;
               Res.Diagnostic_Len := L;
               if L > 0 then
                  Res.Diagnostic (1 .. L) := P_Res.Error_Reason (1 .. L);
               end if;
               return Res;
            end;
         end if;

         declare
            Count : constant Natural := P_Res.Windows.Count;
            Res   : Window_View (Count);
         begin
            Res.Snapshot_Len := Snap_Len;
            Res.Snapshot (1 .. Snap_Len) := Snap (Snap'First .. Snap'First + Snap_Len - 1);
            Res.Status := Query_Complete;
            Res.Window_Count := Count;

            for I in 1 .. Count loop
               Res.Windows (I) := P_Res.Windows.Windows (I);
            end loop;

            return Res;
         end;
      end;
   end Execute_Window_Query;

end HRA_N.Application.Policy_Query;
