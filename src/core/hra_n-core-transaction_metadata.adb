package body HRA_N.Core.Transaction_Metadata is

   function Metadata_Event_Ids_Are_Unique (Entries : Metadata_List) return Boolean is
   begin
      for I in 1 .. Entries.Count loop
         for J in I + 1 .. Entries.Count loop
            if Equal_Token
              (Entries.Values (I).Event.Token, Entries.Values (J).Event.Token)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Metadata_Event_Ids_Are_Unique;

   function Replacement_References_Are_Closed
     (Entries : Metadata_List) return Boolean
   is
   begin
      for I in 1 .. Entries.Count loop
         if Entries.Values (I).Replaces.Present then
            declare
               Found : Boolean := False;
            begin
               for J in 1 .. Entries.Count loop
                  Found := Found or else Equal_Token
                    (Entries.Values (I).Replaces.Value.Token,
                     Entries.Values (J).Event.Token);
               end loop;
               if not Found then
                  return False;
               end if;
            end;
         end if;
      end loop;
      return True;
   end Replacement_References_Are_Closed;

   function Replacements_Are_One_To_One (Entries : Metadata_List) return Boolean is
   begin
      for I in 1 .. Entries.Count loop
         if Entries.Values (I).Replaces.Present then
            for J in I + 1 .. Entries.Count loop
               if Entries.Values (J).Replaces.Present
                 and then Equal_Token
                   (Entries.Values (I).Replaces.Value.Token,
                    Entries.Values (J).Replaces.Value.Token)
               then
                  return False;
               end if;
            end loop;
         end if;
      end loop;
      return True;
   end Replacements_Are_One_To_One;

   function Replacements_Are_Acyclic (Entries : Metadata_List) return Boolean is
   begin
      for Start in 1 .. Entries.Count loop
         declare
            Current : Event_Id := Entries.Values (Start).Event;
            Advanced : Boolean;
         begin
            for Step in 1 .. Entries.Count loop
               Advanced := False;
               for I in 1 .. Entries.Count loop
                  if Equal_Token
                    (Entries.Values (I).Event.Token, Current.Token)
                    and then Entries.Values (I).Replaces.Present
                  then
                     Current := Entries.Values (I).Replaces.Value;
                     Advanced := True;
                  end if;
               end loop;
               if not Advanced then
                  exit;
               elsif Equal_Token
                 (Current.Token, Entries.Values (Start).Event.Token)
               then
                  return False;
               end if;
            end loop;
         end;
      end loop;
      return True;
   end Replacements_Are_Acyclic;

   function Reversal_References_Are_Closed
     (Entries : Metadata_List) return Boolean
   is
   begin
      for I in 1 .. Entries.Count loop
         if Entries.Values (I).Reverses.Present then
            declare
               Found : Boolean := False;
            begin
               for J in 1 .. Entries.Count loop
                  Found := Found or else Equal_Token
                    (Entries.Values (I).Reverses.Value.Token,
                     Entries.Values (J).Event.Token);
               end loop;
               if not Found then
                  return False;
               end if;
            end;
         end if;
      end loop;
      return True;
   end Reversal_References_Are_Closed;

   function Reversals_Are_One_To_One (Entries : Metadata_List) return Boolean is
   begin
      for I in 1 .. Entries.Count loop
         if Entries.Values (I).Reverses.Present then
            for J in I + 1 .. Entries.Count loop
               if Entries.Values (J).Reverses.Present
                 and then Equal_Token
                   (Entries.Values (I).Reverses.Value.Token,
                    Entries.Values (J).Reverses.Value.Token)
               then
                  return False;
               end if;
            end loop;
         end if;
      end loop;
      return True;
   end Reversals_Are_One_To_One;

   function Reversals_Have_No_Chains (Entries : Metadata_List) return Boolean is
   begin
      for I in 1 .. Entries.Count loop
         if Entries.Values (I).Reverses.Present then
            for J in 1 .. Entries.Count loop
               if Entries.Values (J).Reverses.Present
                 and then Equal_Token
                   (Entries.Values (J).Event.Token,
                    Entries.Values (I).Reverses.Value.Token)
               then
                  return False;
               end if;
            end loop;
         end if;
      end loop;
      return True;
   end Reversals_Have_No_Chains;

   function Reversals_Respect_Replacement
     (Entries : Metadata_List) return Boolean
   is
   begin
      for I in 1 .. Entries.Count loop
         if Entries.Values (I).Reverses.Present
           and then Entries.Values (I).Replaces.Present
         then
            return False;
         end if;
         if Entries.Values (I).Reverses.Present then
            for J in 1 .. Entries.Count loop
               if Entries.Values (J).Replaces.Present
                 and then Equal_Token
                   (Entries.Values (J).Replaces.Value.Token,
                    Entries.Values (I).Reverses.Value.Token)
               then
                  return False;
               end if;
            end loop;
         end if;
      end loop;
      return True;
   end Reversals_Respect_Replacement;

   function Make_Metadata_Memory (Entries : Metadata_List) return Metadata_Memory is
     ((Entries => Entries));

   procedure Find_Metadata
     (Memory : in Metadata_Memory;
      Event  : in Event_Id;
      Item   : out Transaction_Metadata_Entry;
      Found  : out Boolean)
   is
   begin
      Item := Empty_Entry;
      Found := False;
      for I in 1 .. Memory.Entries.Count loop
         if Equal_Token
           (Memory.Entries.Values (I).Event.Token, Event.Token)
         then
            Item := Memory.Entries.Values (I);
            Found := True;
            return;
         end if;
      end loop;
   end Find_Metadata;

   procedure Find_Successor
     (Memory    : in Metadata_Memory;
      Target    : in Event_Id;
      Successor : out Event_Id;
      Found     : out Boolean)
   is
   begin
      Successor := (Token => (Length => 0, Value => [others => ' ']));
      Found := False;
      for I in 1 .. Memory.Entries.Count loop
         if Memory.Entries.Values (I).Replaces.Present
           and then Equal_Token
             (Memory.Entries.Values (I).Replaces.Value.Token, Target.Token)
         then
            Successor := Memory.Entries.Values (I).Event;
            Found := True;
            return;
         end if;
      end loop;
   end Find_Successor;

   procedure Find_Reverser
     (Memory   : in Metadata_Memory;
      Target   : in Event_Id;
      Reversal : out Event_Id;
      Found    : out Boolean)
   is
   begin
      Reversal := (Token => (Length => 0, Value => [others => ' ']));
      Found := False;
      for I in 1 .. Memory.Entries.Count loop
         if Memory.Entries.Values (I).Reverses.Present
           and then Equal_Token
             (Memory.Entries.Values (I).Reverses.Value.Token, Target.Token)
         then
            Reversal := Memory.Entries.Values (I).Event;
            Found := True;
            return;
         end if;
      end loop;
   end Find_Reverser;

end HRA_N.Core.Transaction_Metadata;
