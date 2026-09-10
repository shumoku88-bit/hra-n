-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Catalog
-------------------------------------------------------------------------------

package body HRA_N.Core.Catalog with
  SPARK_Mode => On
is

   function Make_Description (S : String) return Description_Text is
      Result : Description_Text;
   begin
      Result.Length := S'Length;
      Result.Value (1 .. S'Length) := S;
      return Result;
   end Make_Description;

   function Make_Catalog
     (Entries : Entry_Array;
      Count   : Entry_Count_Type) return Catalog_Memory
   is
      Result : Catalog_Memory;
   begin
      Result.Count   := Count;
      Result.Entries := Entries;
      return Result;
   end Make_Catalog;

   procedure Find_Entry
     (Mem   : Catalog_Memory;
      Id    : Token_Text;
      Value : out Catalog_Entry;
      Found : out Boolean)
   is
   begin
      Value := Empty_Entry;
      Found := False;
      for I in 1 .. Mem.Count loop
         if Equal_Token (Mem.Entries (I).Id, Id) then
            Value := Mem.Entries (I);
            Found := True;
            return;
         end if;
      end loop;
   end Find_Entry;

   function Entry_At
     (Mem   : Catalog_Memory;
      Index : Entry_Index_Type) return Catalog_Entry is
   begin
      return Mem.Entries (Index);
   end Entry_At;

   function Display_Label
     (Mem : Catalog_Memory;
      Id  : Token_Text) return Token_Text
   is
   begin
      for I in 1 .. Mem.Count loop
         if Equal_Token (Mem.Entries (I).Id, Id)
           and then Mem.Entries (I).Display_Name.Length > 0
         then
            return Mem.Entries (I).Display_Name;
         end if;
      end loop;
      return Id;
   end Display_Label;

end HRA_N.Core.Catalog;
