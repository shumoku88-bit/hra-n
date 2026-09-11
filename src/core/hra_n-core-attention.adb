-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Attention
-------------------------------------------------------------------------------

package body HRA_N.Core.Attention with
  SPARK_Mode => On
is

   function Item_Ids_Are_Unique (Mem : Attention_Memory) return Boolean is
   begin
      for I in 1 .. Mem.Item_Count loop
         for J in I + 1 .. Mem.Item_Count loop
            if Equal_Token (Mem.Items (I).Id, Mem.Items (J).Id) then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Item_Ids_Are_Unique;

   function Closure_References_Are_Closed
     (Mem : Attention_Memory) return Boolean
   is
   begin
      for I in 1 .. Mem.Close_Count loop
         declare
            Found : Boolean := False;
         begin
            for J in 1 .. Mem.Item_Count loop
               Found := Found or else Equal_Token
                 (Mem.Closures (I).Target, Mem.Items (J).Id);
            end loop;
            if not Found then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Closure_References_Are_Closed;

   function Closures_Are_One_To_One (Mem : Attention_Memory) return Boolean is
   begin
      for I in 1 .. Mem.Close_Count loop
         for J in I + 1 .. Mem.Close_Count loop
            if Equal_Token (Mem.Closures (I).Target, Mem.Closures (J).Target) then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Closures_Are_One_To_One;

   function Has_Closure
     (Mem : Attention_Memory;
      Id  : Token_Text) return Boolean
   is
   begin
      for I in 1 .. Mem.Close_Count loop
         if Equal_Token (Mem.Closures (I).Target, Id) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Closure;

   function Is_Open
     (Mem : Attention_Memory;
      Id  : Token_Text) return Boolean
   is
   begin
      for I in 1 .. Mem.Item_Count loop
         if Equal_Token (Mem.Items (I).Id, Id) then
            return not Has_Closure (Mem, Id);
         end if;
      end loop;
      return False;
   end Is_Open;

   function Open_Count (Mem : Attention_Memory) return Item_Count_Type is
      Total : Item_Count_Type := 0;
   begin
      for I in 1 .. Mem.Item_Count loop
         pragma Loop_Invariant (Total <= I - 1);
         if not Has_Closure (Mem, Mem.Items (I).Id) then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Open_Count;

   procedure Find_Item
     (Mem   : Attention_Memory;
      Id    : Token_Text;
      Item  : out Attention_Item;
      Found : out Boolean)
   is
   begin
      Item := Empty_Item;
      Found := False;
      for I in 1 .. Mem.Item_Count loop
         if Equal_Token (Mem.Items (I).Id, Id) then
            Item := Mem.Items (I);
            Found := True;
            return;
         end if;
      end loop;
   end Find_Item;

   procedure Find_Closure
     (Mem     : Attention_Memory;
      Id      : Token_Text;
      Closure : out Attention_Closure;
      Found   : out Boolean)
   is
   begin
      Closure := Empty_Closure;
      Found := False;
      for I in 1 .. Mem.Close_Count loop
         if Equal_Token (Mem.Closures (I).Target, Id) then
            Closure := Mem.Closures (I);
            Found := True;
            return;
         end if;
      end loop;
   end Find_Closure;

end HRA_N.Core.Attention;
