-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Window_Policy
-------------------------------------------------------------------------------

package body HRA_N.Core.Window_Policy with
  SPARK_Mode => On
is

   procedure Find_Window_By_Id
     (Mem   : Window_Memory;
      Id    : Token_Text;
      Win   : out Window_Definition;
      Found : out Boolean)
   is
   begin
      for I in 1 .. Mem.Count loop
         if Equal_Token (Mem.Windows (I).Id, Id) then
            Win   := Mem.Windows (I);
            Found := True;
            return;
         end if;
      end loop;
      Win   := Empty_Window;
      Found := False;
   end Find_Window_By_Id;

   procedure Find_Window_For_Date
     (Mem   : Window_Memory;
      D     : Date_Type;
      Win   : out Window_Definition;
      Found : out Boolean)
   is
   begin
      for I in 1 .. Mem.Count loop
         if Date_In_Window (D, Mem.Windows (I)) then
            Win   := Mem.Windows (I);
            Found := True;
            return;
         end if;
      end loop;
      Win   := Empty_Window;
      Found := False;
   end Find_Window_For_Date;

   function Window_At
     (Mem   : Window_Memory;
      Index : Window_Index_Type) return Window_Definition is
     (Mem.Windows (Index));

end HRA_N.Core.Window_Policy;
