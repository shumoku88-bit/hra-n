with HRA_N.Core.Event; use HRA_N.Core.Event;
package body HRA_N.Application.Correction_Frontier is
   function Event_Exists (Events : Event_Vectors.Vector; Target : Event_Id) return Boolean is
   begin
      for Ev of Events loop
         if Equal_Token (Id (Ev).Token, Target.Token) then return True; end if;
      end loop;
      return False;
   end Event_Exists;

   procedure Successor
     (Memory : Correction_Memory; Target : Event_Id;
      Value : out Event_Id; Found : out Boolean) is
   begin
      Value := Target; Found := False;
      for I in 1 .. Memory.Count loop
         if Equal_Token (Memory.Values (I).Target.Token, Target.Token) then
            Value := Memory.Values (I).Replacement; Found := True; return;
         end if;
      end loop;
   end Successor;

   function Frontier_Admissible
     (Events : Event_Vectors.Vector; Corrections : Correction_Memory) return Boolean is
   begin
      if not Ids_Are_Unique (Corrections) then return False; end if;
      for I in 1 .. Corrections.Count loop
         if not Event_Exists (Events, Corrections.Values (I).Target)
           or else not Event_Exists (Events, Corrections.Values (I).Replacement)
         then return False; end if;
         for J in I + 1 .. Corrections.Count loop
            if Equal_Token (Corrections.Values (I).Target.Token,
                            Corrections.Values (J).Target.Token)
              or else Equal_Token (Corrections.Values (I).Replacement.Token,
                                   Corrections.Values (J).Replacement.Token)
            then return False; end if;
         end loop;
      end loop;
      for I in 1 .. Corrections.Count loop
         declare
            Start : constant Event_Id := Corrections.Values (I).Target;
            Current : Event_Id := Corrections.Values (I).Replacement;
            Next : Event_Id; Found : Boolean;
         begin
            if Equal_Token (Start.Token, Current.Token) then return False; end if;
            for Step in 1 .. Corrections.Count loop
               Successor (Corrections, Current, Next, Found);
               exit when not Found;
               if Equal_Token (Next.Token, Start.Token) then return False; end if;
               Current := Next;
            end loop;
         end;
      end loop;
      return True;
   end Frontier_Admissible;

   procedure Resolve
     (Events : Event_Vectors.Vector; Corrections : Correction_Memory;
      Original : Event_Id; Result : out Resolution_Result) is
      Current, Next : Event_Id; Found : Boolean;
   begin
      Result := (others => <>);
      if not Event_Exists (Events, Original) then return; end if;
      if not Frontier_Admissible (Events, Corrections) then
         Result.State := Resolution_Unresolved; return;
      end if;
      Current := Original;
      for Step in 1 .. Corrections.Count loop
         Successor (Corrections, Current, Next, Found);
         exit when not Found;
         Current := Next; Result.Depth := Result.Depth + 1;
      end loop;
      Result.State := Resolution_Current; Result.Effective := Current;
   end Resolve;
end HRA_N.Application.Correction_Frontier;
