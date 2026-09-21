-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Bounded_History
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Bounded_History with
  SPARK_Mode => On
is

   procedure Prove_Unique_Event_Position
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

   procedure Prove_Unique_Event_Position
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
   end Prove_Unique_Event_Position;

   function Reference_Lookup
     (Source : Semantic_Image;
      Key    : Event_Id) return Lookup_Result
   is
   begin
      for I in 1 .. Source.Count loop
         if Same_Id (Id (Source.Events (I)), Key) then
            return
              (State    => Found,
               Position => I,
               Value    => Source.Events (I));
         end if;
         pragma Loop_Invariant
           (for all J in 1 .. I =>
              not Same_Id (Id (Source.Events (J)), Key));
      end loop;
      return (State => Not_Found);
   end Reference_Lookup;

   function Derived_Lookup
     (Source : Semantic_Image;
      Index  : Derived_Index;
      Key    : Event_Id) return Lookup_Result
   is
   begin
      if not Index_Is_Qualified (Source, Index) then
         return (State => Invalid_Index);
      end if;

      for I in 1 .. Index.Count loop
         pragma Loop_Invariant
           (for all J in 1 .. I - 1 =>
              not Same_Id (Index.Bindings (J).Key, Key));
         if Same_Id (Index.Bindings (I).Key, Key) then
            declare
               Position : constant Event_Position :=
                 Index.Bindings (I).Position;
               Reference : constant Lookup_Result :=
                 Reference_Lookup (Source, Key);
            begin
               pragma Assert
                 (Same_Id (Id (Source.Events (Position)), Key));
               pragma Assert (Reference.State = Found);
               Prove_Unique_Event_Position
                 (Source, Key, Position, Reference.Position);
               pragma Assert (Reference.Position = Position);
               pragma Assert (Reference.Value = Source.Events (Position));
               pragma Assert
                 (Reference =
                    Lookup_Result'
                      (State    => Found,
                       Position => Position,
                       Value    => Source.Events (Position)));
               return
                 (State    => Found,
                  Position => Position,
                  Value    => Source.Events (Position));
            end;
         end if;
      end loop;
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
   end Derived_Lookup;

   procedure Build_Index
     (Source : Semantic_Image;
      Index  : out Derived_Index;
      Status : out Build_Status)
   is
   begin
      Index :=
        (Snapshot => Source.Snapshot,
         Count    => 0,
         Bindings => [others => <>]);

      if not Event_Ids_Are_Unique (Source) then
         Status := Duplicate_Event_Id;
         return;
      end if;

      Index.Count := Source.Count;
      for I in 1 .. Source.Count loop
         Index.Bindings (I) :=
           (Key      => Id (Source.Events (I)),
            Position => I);
         pragma Loop_Invariant (Index.Count = Source.Count);
         pragma Loop_Invariant (Index.Snapshot = Source.Snapshot);
         pragma Loop_Invariant
           (for all J in 1 .. I =>
              Index.Bindings (J).Position = J
              and then Same_Id
                (Index.Bindings (J).Key, Id (Source.Events (J))));
      end loop;

      Status := Index_Built;
   end Build_Index;

end HRA_N.Core.Actual_Bounded_History;
