-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Replay_Refinement
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Replay_Refinement with
  SPARK_Mode => On
is

   procedure Prove_Unique_Source_Position
     (Source : Semantic_Image;
      Key    : Event_Id;
      Left   : Event_Position;
      Right  : Event_Position)
   with
     Ghost,
     Pre  => Event_Ids_Are_Unique (Source)
       and then Left <= Source.Count
       and then Right <= Source.Count
       and then Same_Id (Id (Source.Events (Left)), Key)
       and then Same_Id (Id (Source.Events (Right)), Key),
     Post => Left = Right;

   procedure Prove_Unique_Source_Position
     (Source : Semantic_Image;
      Key    : Event_Id;
      Left   : Event_Position;
      Right  : Event_Position)
   is
   begin
      if Left < Right then
         pragma Assert
           (not Same_Id
              (Id (Source.Events (Left)), Id (Source.Events (Right))));
         pragma Assert (False);
      elsif Right < Left then
         pragma Assert
           (not Same_Id
              (Id (Source.Events (Right)), Id (Source.Events (Left))));
         pragma Assert (False);
      end if;
   end Prove_Unique_Source_Position;

   function Replay_Lookup
     (Source : Semantic_Image;
      Replay : Replay_View;
      Index  : Replay_Index;
      Key    : Event_Id) return Lookup_Result
   is
   begin
      if not Replay_Index_Is_Qualified (Source, Replay, Index) then
         return (State => Invalid_Index);
      end if;

      for I in 1 .. Index.Count loop
         pragma Loop_Invariant
           (for all J in 1 .. I - 1 =>
              not Same_Id (Index.Bindings (J).Key, Key));

         if Same_Id (Index.Bindings (I).Key, Key) then
            declare
               Locator : constant Event_Position :=
                 Event_Position (Index.Bindings (I).Locator);
               Reference : constant Lookup_Result :=
                 Reference_Lookup (Source, Key);
            begin
               pragma Assert
                 (Index.Bindings (I).Key = Id (Source.Events (I)));
               pragma Assert
                 (Same_Id (Id (Source.Events (I)), Key));
               pragma Assert (Reference.State = Found);
               Prove_Unique_Source_Position
                 (Source, Key, I, Reference.Position);
               pragma Assert (Reference.Position = I);
               pragma Assert
                 (Reference.Value = Source.Events (I));
               pragma Assert
                 (Replay.Slots (Locator) = Source.Events (I));
               pragma Assert
                 (Reference.Value = Replay.Slots (Locator));
               return
                 (State    => Found,
                  Position => I,
                  Value    => Replay.Slots (Locator));
            end;
         end if;
      end loop;

      pragma Assert
        (for all J in 1 .. Index.Count =>
           not Same_Id (Index.Bindings (J).Key, Key));
      pragma Assert (Index.Count = Source.Count);
      pragma Assert
        (for all J in 1 .. Source.Count =>
           Index.Bindings (J).Key = Id (Source.Events (J)));
      pragma Assert
        (for all J in 1 .. Source.Count =>
           not Same_Id (Id (Source.Events (J)), Key));

      declare
         Reference : constant Lookup_Result := Reference_Lookup (Source, Key);
      begin
         pragma Assert (Reference.State = Not_Found);
         pragma Assert
           (Reference = Lookup_Result'(State => Not_Found));
         return (State => Not_Found);
      end;
   end Replay_Lookup;

end HRA_N.Core.Actual_Replay_Refinement;
