-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Accounting_Role
-------------------------------------------------------------------------------

package body HRA_N.Core.Accounting_Role with
  SPARK_Mode => On
is

   function Has_Role
     (Map   : Role_Map;
      Locus : Locus_Id) return Boolean
   is
   begin
      for I in 1 .. Map.Count loop
         if Equal_Token (Map.Entries (I).Locus.Token, Locus.Token) then
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
         if Equal_Token (Map.Entries (I).Locus.Token, Locus.Token) then
            Role  := Map.Entries (I).Role;
            Found := True;
            return;
         end if;
      end loop;
      Role  := Role_Asset;
      Found := False;
   end Find_Role;

   function Entry_At
     (Map   : Role_Map;
      Index : Assignment_Index_Type) return Role_Assignment is
     (Map.Entries (Index));

end HRA_N.Core.Accounting_Role;
