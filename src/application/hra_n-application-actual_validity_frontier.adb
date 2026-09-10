-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Actual_Validity_Frontier
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;

package body HRA_N.Application.Actual_Validity_Frontier is

   function Frontier_Admissible (History : Validity_History) return Boolean is
   begin
      if not Fact_Ids_Are_Unique (History) then
         return False;
      end if;
      if not Correction_Ids_Are_Unique (History) then
         return False;
      end if;

      --  Every correction must reference existing facts and preserve Event_Id
      for I in 1 .. History.Correction_Count loop
         declare
            C : constant Validity_Correction := History.Corrections (I);
            T_Fact, R_Fact : Validity_Fact;
            Found_T, Found_R : Boolean;
         begin
            if Equal_Token (C.Target.Token, C.Replacement.Token) then
               return False;
            end if;
            Find_Fact_By_Id (History, C.Target, T_Fact, Found_T);
            if not Found_T then
               return False;
            end if;
            Find_Fact_By_Id (History, C.Replacement, R_Fact, Found_R);
            if not Found_R then
               return False;
            end if;
            if not Equal_Token (T_Fact.Event_Id.Token, R_Fact.Event_Id.Token) then
               return False; -- Preserves event!
            end if;
         end;
      end loop;

      --  No two corrections may have the same Target (no sibling branches)
      for I in 1 .. History.Correction_Count loop
         for J in I + 1 .. History.Correction_Count loop
            if Equal_Token (History.Corrections (I).Target.Token,
                            History.Corrections (J).Target.Token)
            then
               return False;
            end if;
         end loop;
      end loop;

      --  No two corrections may have the same Replacement (no confluent merges)
      for I in 1 .. History.Correction_Count loop
         for J in I + 1 .. History.Correction_Count loop
            if Equal_Token (History.Corrections (I).Replacement.Token,
                            History.Corrections (J).Replacement.Token)
            then
               return False;
            end if;
         end loop;
      end loop;

      --  Acyclicity
      for I in 1 .. History.Correction_Count loop
         declare
            Curr : Validity_Fact_Id := History.Corrections (I).Replacement;
            Hops : Natural := 0;
            Adv  : Boolean := True;
         begin
            while Adv loop
               Adv := False;
               for J in 1 .. History.Correction_Count loop
                  if Equal_Token (History.Corrections (J).Target.Token, Curr.Token) then
                     Curr := History.Corrections (J).Replacement;
                     Hops := Hops + 1;
                     if Hops > History.Correction_Count
                       or else Equal_Token (Curr.Token, History.Corrections (I).Target.Token)
                     then
                        return False;
                     end if;
                     Adv := True;
                     exit;
                  end if;
               end loop;
            end loop;
         end;
      end loop;

      --  In frontier facts: no two facts share an Event_Id
      for I in 1 .. History.Fact_Count loop
         declare
            Is_Target_I : Boolean := False;
         begin
            for C in 1 .. History.Correction_Count loop
               if Equal_Token (History.Corrections (C).Target.Token, History.Facts (I).Id.Token) then
                  Is_Target_I := True;
                  exit;
               end if;
            end loop;

            if not Is_Target_I then
               for J in I + 1 .. History.Fact_Count loop
                  declare
                     Is_Target_J : Boolean := False;
                  begin
                     for C in 1 .. History.Correction_Count loop
                        if Equal_Token (History.Corrections (C).Target.Token, History.Facts (J).Id.Token) then
                           Is_Target_J := True;
                           exit;
                        end if;
                     end loop;

                     if not Is_Target_J then
                        if Equal_Token (History.Facts (I).Event_Id.Token, History.Facts (J).Event_Id.Token) then
                           return False; -- Multiple current facts for same Event!
                        end if;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      return True;
   end Frontier_Admissible;

   function Project_Memory
     (History : Validity_History;
      Memory  : out Validity_Memory) return Boolean
   is
      Entries : Validity_Entry_List;
   begin
      if not Frontier_Admissible (History) then
         return False;
      end if;

      for I in 1 .. History.Fact_Count loop
         declare
            Is_Target : Boolean := False;
         begin
            for C in 1 .. History.Correction_Count loop
               if Equal_Token (History.Corrections (C).Target.Token, History.Facts (I).Id.Token) then
                  Is_Target := True;
                  exit;
               end if;
            end loop;

            if not Is_Target then
               if Entries.Count = Max_Validity_Entries then
                  return False;
               end if;
               Entries.Count := Entries.Count + 1;
               Entries.Values (Entries.Count) :=
                 (Event_Id => History.Facts (I).Event_Id,
                  Valid_On => History.Facts (I).Valid_On);
            end if;
         end;
      end loop;

      if not Event_Ids_Are_Unique (Entries) then
         return False;
      end if;

      Memory := Make_Validity_Memory (Entries);
      return True;
   end Project_Memory;

   procedure Find_Current_Fact
     (History : in  Validity_History;
      Target  : in  Event_Id;
      Fact    : out Validity_Fact;
      Found   : out Boolean)
   is
   begin
      Fact  := (Id       => (Token => (Length => 0, Value => [others => ' '])),
                Event_Id => (Token => (Length => 0, Value => [others => ' '])),
                Valid_On => (Year => 2026, Month => 1, Day => 1));
      Found := False;

      if not Frontier_Admissible (History) then
         return;
      end if;

      for I in 1 .. History.Fact_Count loop
         if Equal_Token (History.Facts (I).Event_Id.Token, Target.Token) then
            declare
               Is_Target : Boolean := False;
            begin
               for C in 1 .. History.Correction_Count loop
                  if Equal_Token (History.Corrections (C).Target.Token, History.Facts (I).Id.Token) then
                     Is_Target := True;
                     exit;
                  end if;
               end loop;

               if not Is_Target then
                  Fact  := History.Facts (I);
                  Found := True;
                  return;
               end if;
            end;
         end if;
      end loop;
   end Find_Current_Fact;

   function Fresh_Fact_Id (History : Validity_History) return Validity_Fact_Id is
   begin
      for N in 1 .. History.Fact_Count + 1 loop
         declare
            N_Str : constant String := Ada.Strings.Fixed.Trim (Positive'Image (N), Ada.Strings.Both);
            Cand  : constant String := "validity-" & N_Str;
            Id    : constant Validity_Fact_Id := (Token => Make_Token (Cand));
            Fact  : Validity_Fact;
            Found : Boolean;
         begin
            Find_Fact_By_Id (History, Id, Fact, Found);
            if not Found then
               return Id;
            end if;
         end;
      end loop;
      return (Token => (Length => 0, Value => [others => ' ']));
   end Fresh_Fact_Id;

   function Fresh_Correction_Id (History : Validity_History) return Validity_Correction_Id is
   begin
      for N in 1 .. History.Correction_Count + 1 loop
         declare
            N_Str : constant String := Ada.Strings.Fixed.Trim (Positive'Image (N), Ada.Strings.Both);
            Cand  : constant String := "validity-correction-" & N_Str;
            Id    : constant Validity_Correction_Id := (Token => Make_Token (Cand));
            Corr  : Validity_Correction;
            Found : Boolean;
         begin
            Find_Correction_By_Id (History, Id, Corr, Found);
            if not Found then
               return Id;
            end if;
         end;
      end loop;
      return (Token => (Length => 0, Value => [others => ' ']));
   end Fresh_Correction_Id;

end HRA_N.Application.Actual_Validity_Frontier;
