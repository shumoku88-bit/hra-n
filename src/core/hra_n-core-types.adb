-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Types
-------------------------------------------------------------------------------

package body HRA_N.Core.Types with
  SPARK_Mode => On
is

   function Make_Token (S : String) return Token_Text is
      Result : Token_Text;
      Pos    : Natural := 0;
   begin
      Result.Length := S'Length;
      for I in S'Range loop
         Pos := Pos + 1;
         Result.Value (Pos) := S (I);
         pragma Loop_Invariant (Pos = I - S'First + 1);
         pragma Loop_Invariant (Pos <= Result.Length);
      end loop;
      return Result;
   end Make_Token;

end HRA_N.Core.Types;
