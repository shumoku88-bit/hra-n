-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Reader_Refinement
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Reader_Refinement with
  SPARK_Mode => On
is

   procedure Prove_Event_Id_Substitution
     (Left  : HRA_N.Core.Event.Event;
      Right : HRA_N.Core.Event.Event;
      Key   : Event_Id)
   with
     Ghost,
     Pre  => Left = Right and then Same_Id (Id (Left), Key),
     Post => Same_Id (Id (Right), Key);

   procedure Prove_Event_Id_Substitution
     (Left  : HRA_N.Core.Event.Event;
      Right : HRA_N.Core.Event.Event;
      Key   : Event_Id)
   is
   begin
      null;
   end Prove_Event_Id_Substitution;

   procedure Prove_Unique_Production_Position
     (Source : Production_Event_View;
      Key    : Event_Id;
      Left   : Event_Position;
      Right  : Event_Position)
   with
     Ghost,
     Pre  => Production_Ids_Are_Unique (Source)
       and then Left <= Source.Count
       and then Right <= Source.Count
       and then Same_Id (Id (Source.Events (Left)), Key)
       and then Same_Id (Id (Source.Events (Right)), Key),
     Post => Left = Right;

   procedure Prove_Unique_Production_Position
     (Source : Production_Event_View;
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
   end Prove_Unique_Production_Position;

   function Production_Linear_Lookup
     (Source : Production_Event_View;
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
   end Production_Linear_Lookup;

   procedure Refine_Reader_Events
     (Source   : Production_Event_View;
      Snapshot : Snapshot_Id;
      Image    : out Semantic_Image;
      Status   : out Refinement_Status)
   is
   begin
      Image :=
        (Snapshot => Snapshot,
         Count    => 0,
         Events   => Source.Events);

      if not Source.Reader_Succeeded then
         Status := Reader_Failed;
      elsif Source.Count > Max_Events then
         Status := Too_Many_Events;
      elsif not Production_Ids_Are_Unique (Source) then
         Status := Duplicate_Event_Id;
      else
         Image.Count := Source.Count;
         Status := Refined;
      end if;
   end Refine_Reader_Events;

   procedure Prove_Reference_Lookup_Refinement
     (Source : Production_Event_View;
      Image  : Semantic_Image;
      Key    : Event_Id)
   is
      Production_Result : constant Lookup_Result :=
        Production_Linear_Lookup (Source, Key);
      Reference_Result : constant Lookup_Result :=
        Reference_Lookup (Image, Key);
   begin
      if Production_Result.State = Found then
         pragma Assert (Reference_Result.State = Found);
         pragma Assert (Reference_Result.Position <= Source.Count);
         pragma Assert
           (Reference_Result.Value =
              Image.Events (Reference_Result.Position));
         pragma Assert
           (Image.Events (Reference_Result.Position) =
              Source.Events (Reference_Result.Position));
         pragma Assert
           (Same_Id (Id (Reference_Result.Value), Key));
         Prove_Event_Id_Substitution
           (Reference_Result.Value,
            Image.Events (Reference_Result.Position),
            Key);
         Prove_Event_Id_Substitution
           (Image.Events (Reference_Result.Position),
            Source.Events (Reference_Result.Position),
            Key);
         pragma Assert
           (Production_Result.Value =
              Source.Events (Production_Result.Position));
         Prove_Event_Id_Substitution
           (Production_Result.Value,
            Source.Events (Production_Result.Position),
            Key);
         Prove_Unique_Production_Position
           (Source,
            Key,
            Production_Result.Position,
            Reference_Result.Position);
         pragma Assert
           (Production_Result.Position = Reference_Result.Position);
         pragma Assert
           (Production_Result.Value = Reference_Result.Value);
      else
         pragma Assert (Production_Result.State = Not_Found);
         pragma Assert (Reference_Result.State = Not_Found);
      end if;
      pragma Assert (Production_Result = Reference_Result);
   end Prove_Reference_Lookup_Refinement;

end HRA_N.Core.Actual_Reader_Refinement;
