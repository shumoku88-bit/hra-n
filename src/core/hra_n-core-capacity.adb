-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Capacity
-------------------------------------------------------------------------------

package body HRA_N.Core.Capacity with
  SPARK_Mode => On
is

   ----------------------------------------------------------------------------
   --  Sum_Changes
   ----------------------------------------------------------------------------
   function Sum_Changes (Mov : Capacity_Movement) return Long_Long_Integer is
      Total : Long_Long_Integer := 0;
   begin
      for I in 1 .. Mov.Change_Count loop
         pragma Loop_Invariant
           (Total >= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'First)
            and then Total <= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'Last));
         Total := Total + Long_Long_Integer (Mov.Changes (I).Amount);
      end loop;
      return Total;
   end Sum_Changes;

   ----------------------------------------------------------------------------
   --  Quantity_At
   ----------------------------------------------------------------------------
   function Quantity_At
     (Mov   : Capacity_Movement;
      Coord : Capacity_Coordinate) return Quanta_Type
   is
      Total : Long_Long_Integer := 0;
   begin
      for I in 1 .. Mov.Change_Count loop
         pragma Loop_Invariant
           (Total >= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'First)
            and then Total <= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'Last));
         if Equal_Coordinate (Mov.Changes (I).Coord, Coord) then
            Total := Total + Long_Long_Integer (Mov.Changes (I).Amount);
         end if;
      end loop;

      if Total > Long_Long_Integer (Quanta_Type'Last) then
         return Quanta_Type'Last;
      elsif Total < Long_Long_Integer (Quanta_Type'First) then
         return Quanta_Type'First;
      else
         return Quanta_Type (Total);
      end if;
   end Quantity_At;

   ----------------------------------------------------------------------------
   --  Find_Effective_Date
   ----------------------------------------------------------------------------
   procedure Find_Effective_Date
     (Mem         : Capacity_Memory;
      Movement_Id : Token_Text;
      Year        : out Natural;
      Month       : out Natural;
      Day         : out Natural;
      Found       : out Boolean)
   is
   begin
      Year  := 0;
      Month := 0;
      Day   := 0;
      Found := False;

      for I in 1 .. Mem.Effective_Count loop
         if Equal_Token (Mem.Effective (I).Movement_Id, Movement_Id) then
            Year  := Mem.Effective (I).Year;
            Month := Mem.Effective (I).Month;
            Day   := Mem.Effective (I).Day;
            Found := True;
            return;
         end if;
      end loop;
   end Find_Effective_Date;

   ----------------------------------------------------------------------------
   --  Has_Effective_Date
   ----------------------------------------------------------------------------
   function Has_Effective_Date
     (Mem         : Capacity_Memory;
      Movement_Id : Token_Text) return Boolean
   is
   begin
      for I in 1 .. Mem.Effective_Count loop
         if Equal_Token (Mem.Effective (I).Movement_Id, Movement_Id) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Effective_Date;

   ----------------------------------------------------------------------------
   --  All_Movements_Conserved
   ----------------------------------------------------------------------------
   function All_Movements_Conserved (Mem : Capacity_Memory) return Boolean is
   begin
      for I in 1 .. Mem.Movement_Count loop
         if not Is_Conserved (Mem.Movements (I)) then
            return False;
         end if;
      end loop;
      return True;
   end All_Movements_Conserved;

   ----------------------------------------------------------------------------
   --  Effective_Evidence_Complete
   ----------------------------------------------------------------------------
   function Effective_Evidence_Complete (Mem : Capacity_Memory) return Boolean is
      Found : Boolean;
   begin
      --  1. Every movement must have an effective date
      for I in 1 .. Mem.Movement_Count loop
         if not Has_Effective_Date (Mem, Mem.Movements (I).Id) then
            return False;
         end if;
      end loop;

      --  2. No orphan effective entries (every effective must correspond to a movement)
      for I in 1 .. Mem.Effective_Count loop
         Found := False;
         for J in 1 .. Mem.Movement_Count loop
            if Equal_Token (Mem.Movements (J).Id, Mem.Effective (I).Movement_Id) then
               Found := True;
               exit;
            end if;
         end loop;
         if not Found then
            return False;
         end if;
      end loop;

      return True;
   end Effective_Evidence_Complete;

   ----------------------------------------------------------------------------
   --  Effective_References_Are_Closed
   ----------------------------------------------------------------------------
   function Effective_References_Are_Closed
     (Mem : Capacity_Memory) return Boolean
   is
   begin
      for I in 1 .. Mem.Effective_Count loop
         declare
            Found : Boolean := False;
         begin
            for J in 1 .. Mem.Movement_Count loop
               Found := Found or else Equal_Token
                 (Mem.Effective (I).Movement_Id, Mem.Movements (J).Id);
            end loop;
            if not Found then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Effective_References_Are_Closed;

   ----------------------------------------------------------------------------
   --  Effectives_Are_One_To_One
   ----------------------------------------------------------------------------
   function Effectives_Are_One_To_One
     (Mem : Capacity_Memory) return Boolean
   is
   begin
      for I in 1 .. Mem.Effective_Count loop
         for J in I + 1 .. Mem.Effective_Count loop
            if Equal_Token
              (Mem.Effective (I).Movement_Id, Mem.Effective (J).Movement_Id)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Effectives_Are_One_To_One;

   ----------------------------------------------------------------------------
   --  Entitlement_At
   ----------------------------------------------------------------------------
   function Entitlement_At
     (Mem      : Capacity_Memory;
      Coord    : Capacity_Coordinate;
      Currency : Token_Text) return Quanta_Type
   is
      Total : Long_Long_Integer := 0;
   begin
      for I in 1 .. Mem.Movement_Count loop
         pragma Loop_Invariant
           (Total >= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'First)
            and then Total <= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'Last));
         if Equal_Token (Mem.Movements (I).Currency, Currency) then
            Total := Total +
              Long_Long_Integer (Quantity_At (Mem.Movements (I), Coord));
         end if;
      end loop;

      if Total > Long_Long_Integer (Quanta_Type'Last) then
         return Quanta_Type'Last;
      elsif Total < Long_Long_Integer (Quanta_Type'First) then
         return Quanta_Type'First;
      else
         return Quanta_Type (Total);
      end if;
   end Entitlement_At;

end HRA_N.Core.Capacity;
