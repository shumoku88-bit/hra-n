-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Accounting_Role
-------------------------------------------------------------------------------

package body HRA_N.Core.Accounting_Role with
  SPARK_Mode => On
is

   function Has_Successor
     (Map : Role_Map;
      Id  : Token_Text) return Boolean
   is
   begin
      if Id.Length = 0 then
         return False;
      end if;
      for I in 1 .. Map.Count loop
         if Map.Entries (I).Has_Replaces
           and then Equal_Token (Map.Entries (I).Replaces, Id)
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Successor;

   function Replacement_History_Is_Acyclic (Map : Role_Map) return Boolean is
   begin
      for I in 1 .. Map.Count loop
         if Map.Entries (I).Has_Replaces then
            declare
               Curr_Target : Token_Text := Map.Entries (I).Replaces;
               Steps       : Natural := 0;
            begin
               while Steps <= Map.Count loop
                  pragma Loop_Variant (Increases => Steps);
                  pragma Loop_Invariant (Steps <= Map.Count + 1);
                  if Equal_Token (Curr_Target, Map.Entries (I).Id) then
                     return False;  --  Cycle detected
                  end if;

                  declare
                     Next_Target : Token_Text := (Length => 0, Value => [others => ' ']);
                     Has_Next    : Boolean := False;
                  begin
                     for J in 1 .. Map.Count loop
                        if Equal_Token (Map.Entries (J).Id, Curr_Target) then
                           if Map.Entries (J).Has_Replaces then
                              Next_Target := Map.Entries (J).Replaces;
                              Has_Next := True;
                           end if;
                           exit;
                        end if;
                     end loop;

                     if not Has_Next then
                        exit;  --  Reached root of replacement chain
                     end if;
                     Curr_Target := Next_Target;
                  end;
                  Steps := Steps + 1;
               end loop;

               if Steps > Map.Count then
                  return False;  --  Cycle detected by step bound
               end if;
            end;
         end if;
      end loop;
      return True;
   end Replacement_History_Is_Acyclic;

   function Has_Role
     (Map   : Role_Map;
      Locus : Locus_Id) return Boolean
   is
   begin
      for I in 1 .. Map.Count loop
         if Equal_Token (Map.Entries (I).Locus.Token, Locus.Token)
           and then not Has_Successor (Map, Map.Entries (I).Id)
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Role;

   procedure Find_Role
     (Map   : Role_Map;
      Locus : Locus_Id;
      Role  : out Accounting_Role;
      Found : out Boolean)
   is
   begin
      for I in 1 .. Map.Count loop
         if Equal_Token (Map.Entries (I).Locus.Token, Locus.Token)
           and then not Has_Successor (Map, Map.Entries (I).Id)
         then
            Role  := Map.Entries (I).Role;
            Found := True;
            return;
         end if;
      end loop;
      Role  := Role_Asset;
      Found := False;
   end Find_Role;

   procedure Find_Assignment_As_Of
     (Map   : Role_Map;
      Locus : Locus_Id;
      As_Of : Date_Type;
      Item  : out Role_Assignment;
      Found : out Boolean)
   is
   begin
      --  Find assignment that is effective on or before As_Of,
      --  and is not superseded by another assignment effective on or before As_Of.
      for I in 1 .. Map.Count loop
         if Equal_Token (Map.Entries (I).Locus.Token, Locus.Token)
           and then Date_Less_Or_Equal (Map.Entries (I).Effective_From, As_Of)
         then
            declare
               Is_Superseded_As_Of : Boolean := False;
            begin
               for J in 1 .. Map.Count loop
                  if Map.Entries (J).Has_Replaces
                    and then Equal_Token (Map.Entries (J).Replaces, Map.Entries (I).Id)
                    and then Date_Less_Or_Equal (Map.Entries (J).Effective_From, As_Of)
                  then
                     Is_Superseded_As_Of := True;
                     exit;
                  end if;
               end loop;

               if not Is_Superseded_As_Of then
                  Item  := Map.Entries (I);
                  Found := True;
                  return;
               end if;
            end;
         end if;
      end loop;
      Item  := Empty_Assignment;
      Found := False;
   end Find_Assignment_As_Of;

   procedure Find_Role_As_Of
     (Map   : Role_Map;
      Locus : Locus_Id;
      As_Of : Date_Type;
      Role  : out Accounting_Role;
      Found : out Boolean)
   is
      Item : Role_Assignment;
   begin
      Find_Assignment_As_Of (Map, Locus, As_Of, Item, Found);
      if Found then
         Role := Item.Role;
      else
         Role := Role_Asset;
      end if;
   end Find_Role_As_Of;

   procedure Find_Assignment_By_Id
     (Map   : Role_Map;
      Id    : Token_Text;
      Item  : out Role_Assignment;
      Found : out Boolean)
   is
   begin
      for I in 1 .. Map.Count loop
         if Equal_Token (Map.Entries (I).Id, Id) then
            Item  := Map.Entries (I);
            Found := True;
            return;
         end if;
      end loop;
      Item  := Empty_Assignment;
      Found := False;
   end Find_Assignment_By_Id;

   procedure Find_Successor
     (Map   : Role_Map;
      Id    : Token_Text;
      Succ  : out Role_Assignment;
      Found : out Boolean)
   is
   begin
      for I in 1 .. Map.Count loop
         if Map.Entries (I).Has_Replaces
           and then Equal_Token (Map.Entries (I).Replaces, Id)
         then
            Succ  := Map.Entries (I);
            Found := True;
            return;
         end if;
      end loop;
      Succ  := Empty_Assignment;
      Found := False;
   end Find_Successor;

   function Active_Count (Map : Role_Map) return Natural is
      Result : Natural := 0;
   begin
      for I in 1 .. Map.Count loop
         pragma Loop_Invariant (Result <= I);
         if not Has_Successor (Map, Map.Entries (I).Id) then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Active_Count;

   function Active_Entry_At
     (Map   : Role_Map;
      Index : Positive) return Role_Assignment
   is
      Current : Natural := 0;
   begin
      for I in 1 .. Map.Count loop
         pragma Loop_Invariant (Current <= I);
         if not Has_Successor (Map, Map.Entries (I).Id) then
            Current := Current + 1;
            if Current = Index then
               return Map.Entries (I);
            end if;
         end if;
      end loop;
      return Empty_Assignment;
   end Active_Entry_At;

   function Entry_At
     (Map   : Role_Map;
      Index : Assignment_Index_Type) return Role_Assignment is
     (Map.Entries (Index));

end HRA_N.Core.Accounting_Role;
