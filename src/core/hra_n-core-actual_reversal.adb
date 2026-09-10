-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Reversal
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Reversal with
  SPARK_Mode => On
is

   function Is_Target_Reversed
     (Mem    : Reversal_Memory;
      Target : Event_Id) return Boolean
   is
   begin
      for I in 1 .. Mem.Count loop
         if Equal_Token (Mem.Entries (I).Target.Token, Target.Token) then
            return True;
         end if;
      end loop;
      return False;
   end Is_Target_Reversed;

   procedure Find_Reversal_For
     (Mem      : Reversal_Memory;
      Target   : Event_Id;
      Reversal : out Event_Id;
      Found    : out Boolean)
   is
   begin
      for I in 1 .. Mem.Count loop
         if Equal_Token (Mem.Entries (I).Target.Token, Target.Token) then
            Reversal := Mem.Entries (I).Reversal;
            Found    := True;
            return;
         end if;
      end loop;
      Reversal := (Token => (Length => 0, Value => [others => ' ']));
      Found    := False;
   end Find_Reversal_For;

   function Entry_At
     (Mem   : Reversal_Memory;
      Index : Reversal_Index_Type) return Actual_Reversal is
     (Mem.Entries (Index));

end HRA_N.Core.Actual_Reversal;
