-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Relation
-------------------------------------------------------------------------------

package body HRA_N.Core.Relation with
  SPARK_Mode => On
is

   function Claim_Ids_Are_Unique (Mem : Relation_Memory) return Boolean is
   begin
      for I in 1 .. Mem.Claim_Count loop
         for J in I + 1 .. Mem.Claim_Count loop
            if Equal_Token (Mem.Claims (I).Id, Mem.Claims (J).Id) then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Claim_Ids_Are_Unique;

   function Discharge_Pairs_Are_Unique
     (Mem : Relation_Memory) return Boolean
   is
   begin
      for I in 1 .. Mem.Discharge_Count loop
         for J in I + 1 .. Mem.Discharge_Count loop
            if Equal_Token
                 (Mem.Discharges (I).Settlement.Token,
                  Mem.Discharges (J).Settlement.Token)
              and then Equal_Token
                 (Mem.Discharges (I).Target, Mem.Discharges (J).Target)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Discharge_Pairs_Are_Unique;

   function Discharged_Against
     (Mem      : Relation_Memory;
      Claim_Id : Token_Text) return Long_Long_Integer
   is
      Total : Long_Long_Integer := 0;
   begin
      for I in 1 .. Mem.Discharge_Count loop
         pragma Loop_Invariant
           (Total >= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'First)
            and then Total <= Long_Long_Integer (I - 1) * Long_Long_Integer (Quanta_Type'Last));
         if Equal_Token (Mem.Discharges (I).Target, Claim_Id) then
            Total := Total + Long_Long_Integer (Mem.Discharges (I).Amount);
         end if;
      end loop;
      return Total;
   end Discharged_Against;

   function Remaining_For
     (Mem      : Relation_Memory;
      Claim_Id : Token_Text) return Long_Long_Integer
   is
   begin
      for I in 1 .. Mem.Claim_Count loop
         if Equal_Token (Mem.Claims (I).Id, Claim_Id) then
            return Long_Long_Integer (Mem.Claims (I).Face)
              - Discharged_Against (Mem, Claim_Id);
         end if;
      end loop;
      return 0;
   end Remaining_For;

   function Involves_Event
     (Mem    : Relation_Memory;
      Target : Event_Id) return Boolean
   is
   begin
      for I in 1 .. Mem.Claim_Count loop
         if Equal_Token (Mem.Claims (I).Source.Token, Target.Token) then
            return True;
         end if;
      end loop;
      for I in 1 .. Mem.Discharge_Count loop
         if Equal_Token (Mem.Discharges (I).Settlement.Token, Target.Token) then
            return True;
         end if;
      end loop;
      return False;
   end Involves_Event;

   procedure Find_Claim
     (Mem   : Relation_Memory;
      Id    : Token_Text;
      Claim : out Relation_Claim;
      Found : out Boolean)
   is
   begin
      Claim := Empty_Claim;
      Found := False;
      for I in 1 .. Mem.Claim_Count loop
         if Equal_Token (Mem.Claims (I).Id, Id) then
            Claim := Mem.Claims (I);
            Found := True;
            return;
         end if;
      end loop;
   end Find_Claim;

end HRA_N.Core.Relation;
