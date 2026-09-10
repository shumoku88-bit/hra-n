-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Description
-------------------------------------------------------------------------------

package body HRA_N.Core.Description with
  SPARK_Mode => On
is

   function Make_Description (S : String) return Description_Text is
      Result : Description_Text;
   begin
      Result.Length := S'Length;
      Result.Value (1 .. S'Length) := S;
      return Result;
   end Make_Description;

   function Make_Description_Memory
     (Entries : Description_Entry_List) return Description_Memory
   is
   begin
      return (Entries => Entries);
   end Make_Description_Memory;

   procedure Find_Description
     (Memory : in  Description_Memory;
      Ev_Id  : in  Types.Event_Id;
      Text   : out Description_Text;
      Found  : out Boolean)
   is
   begin
      for I in 1 .. Memory.Entries.Count loop
         if Equal_Token (Memory.Entries.Values (I).Event_Id.Token, Ev_Id.Token) then
            Text  := Memory.Entries.Values (I).Text;
            Found := True;
            return;
         end if;
      end loop;
      Text  := (Length => 0, Value => [others => ' ']);
      Found := False;
   end Find_Description;

end HRA_N.Core.Description;
