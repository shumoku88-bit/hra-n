-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Policy_Query
-------------------------------------------------------------------------------

with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Policy_Query is

   function Execute_Locus_Query (Paths : Path_Config) return Locus_View is
      Snap     : constant String := Snapshot_Id_Str (Paths);
      Snap_Len : constant Natural := Natural'Min (Snap'Length, 64);
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         declare
            Res : Locus_View (0);
         begin
            Res.Status := Query_Rejected;
            Res.Diagnostic (1 .. 32) := "Unresolvable snapshot authority ";
            Res.Diagnostic_Len := 32;
            return Res;
         end;
      end if;

      declare
         Policy : constant Policy_Result :=
           Read_Policy_File (Policy_Path_Str (Paths));
      begin
         if not Policy.Success then
            declare
               Res : Locus_View (0);
               Len : constant Natural :=
                 Natural'Min (Policy.Error_Len, Res.Diagnostic'Length);
            begin
               Res.Status := Query_Rejected;
               Res.Diagnostic_Len := Len;
               if Len > 0 then
                  Res.Diagnostic (1 .. Len) :=
                    Policy.Error_Reason (1 .. Len);
               end if;
               return Res;
            end;
         end if;

         declare
            Res : Locus_View (Natural (Policy.Loci.Count));
         begin
            Res.Snapshot_Len := Snap_Len;
            Res.Snapshot (1 .. Snap_Len) :=
              Snap (Snap'First .. Snap'First + Snap_Len - 1);
            Res.Status := Query_Complete;
            Res.Row_Count := Natural (Policy.Loci.Count);
            for I in 1 .. Policy.Loci.Count loop
               Res.Rows (I) := Policy.Loci.Values (I).Token;
            end loop;
            for I in 1 .. Res.Row_Count loop
               for J in I + 1 .. Res.Row_Count loop
                  if Token_Less (Res.Rows (J), Res.Rows (I)) then
                     declare
                        Temp : constant Token_Text := Res.Rows (I);
                     begin
                        Res.Rows (I) := Res.Rows (J);
                        Res.Rows (J) := Temp;
                     end;
                  end if;
               end loop;
            end loop;
            return Res;
         end;
      end;
   end Execute_Locus_Query;

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

   function Execute_Routing_Query
     (Paths           : Path_Config;
      As_Of           : Date_Type;
      Include_History : Boolean := False) return Routing_View
   is
      Snap     : constant String := Snapshot_Id_Str (Paths);
      Snap_Len : constant Natural := Natural'Min (Snap'Length, 64);
   begin
      if not Paths.Resolution_Ok or else not Paths.Is_Versioned then
         declare
            Res : Routing_View (0);
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
               Res : Routing_View (0);
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
            Res : Routing_View (Natural (P_Res.Routing.Count));

            function Applicable (Item : Routing_Entry) return Boolean is
              (Item.Effective_Kind = Routing_Initial
               or else Date_Less (Item.Effective_On, As_Of)
               or else Equal_Date (Item.Effective_On, As_Of));

            function Later
              (Candidate, Current : Routing_Entry) return Boolean is
              ((Current.Effective_Kind = Routing_Initial
                and then Candidate.Effective_Kind = Routing_From_Date)
               or else (Current.Effective_Kind = Routing_From_Date
                         and then Candidate.Effective_Kind = Routing_From_Date
                         and then Date_Less
                           (Current.Effective_On, Candidate.Effective_On)));

            procedure Add (Item : Routing_Entry) is
            begin
               Res.Row_Count := Res.Row_Count + 1;
               Res.Rows (Res.Row_Count) :=
                 (Locus          => Item.Locus.Token,
                  Effective_Kind => Item.Effective_Kind,
                  Effective_On   => Item.Effective_On,
                  Managed        => Item.Managed,
                  Purpose        => Item.Purpose);
            end Add;
         begin
            Res.Snapshot_Len := Snap_Len;
            Res.Snapshot (1 .. Snap_Len) :=
              Snap (Snap'First .. Snap'First + Snap_Len - 1);
            Res.Status := Query_Complete;
            Res.As_Of_Date := As_Of;
            Res.Includes_History := Include_History;

            for I in 1 .. P_Res.Routing.Count loop
               declare
                  Item      : Routing_Entry renames P_Res.Routing.Entries (I);
                  Superseded : Boolean := False;
               begin
                  if Include_History then
                     Add (Item);
                  elsif Applicable (Item) then
                     for J in 1 .. P_Res.Routing.Count loop
                        if J /= I
                          and then Applicable (P_Res.Routing.Entries (J))
                          and then Equal_Token
                            (Item.Locus.Token,
                             P_Res.Routing.Entries (J).Locus.Token)
                          and then Later (P_Res.Routing.Entries (J), Item)
                        then
                           Superseded := True;
                           exit;
                        end if;
                     end loop;
                     if not Superseded then
                        Add (Item);
                     end if;
                  end if;
               end;
            end loop;

            for I in 1 .. Res.Row_Count loop
               for J in I + 1 .. Res.Row_Count loop
                  if Token_Less (Res.Rows (J).Locus, Res.Rows (I).Locus)
                    or else
                      (Equal_Token (Res.Rows (J).Locus, Res.Rows (I).Locus)
                       and then Res.Rows (I).Effective_Kind = Routing_From_Date
                       and then
                         (Res.Rows (J).Effective_Kind = Routing_Initial
                          or else Date_Less
                            (Res.Rows (J).Effective_On,
                             Res.Rows (I).Effective_On)))
                  then
                     declare
                        Tmp : constant Routing_View_Row := Res.Rows (I);
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
   end Execute_Routing_Query;

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
