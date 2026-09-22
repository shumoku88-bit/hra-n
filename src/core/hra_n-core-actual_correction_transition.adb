-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Correction_Transition
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Correction_Transition with
  SPARK_Mode => On
is
   use type HRA_N.Core.Event.Event;

   procedure Prove_Same_Id_Transitive
     (Left, Middle, Right : Event_Id)
   with
     Ghost,
     Pre  => Same_Id (Left, Middle) and then Same_Id (Middle, Right),
     Post => Same_Id (Left, Right);

   procedure Prove_Same_Id_Transitive
     (Left, Middle, Right : Event_Id)
   is
   begin
      null;
   end Prove_Same_Id_Transitive;

   procedure Prove_Present_Not_Fresh
     (Source      : Semantic_Image;
      Key         : Event_Id;
      Replacement : HRA_N.Core.Event.Event)
   with
     Ghost,
     Pre =>
       (for some I in 1 .. Source.Count =>
          Same_Id (HRA_N.Core.Event.Id (Source.Events (I)), Key))
       and then Fresh_For (Source, Replacement),
     Post =>
       not Same_Id
         (Key, HRA_N.Core.Event.Id (Replacement));

   procedure Prove_Present_Not_Fresh
     (Source      : Semantic_Image;
      Key         : Event_Id;
      Replacement : HRA_N.Core.Event.Event)
   is
   begin
      for I in 1 .. Source.Count loop
         if Same_Id (HRA_N.Core.Event.Id (Source.Events (I)), Key) then
            if Same_Id (Key, HRA_N.Core.Event.Id (Replacement)) then
               Prove_Same_Id_Transitive
                 (HRA_N.Core.Event.Id (Source.Events (I)),
                  Key,
                  HRA_N.Core.Event.Id (Replacement));
               pragma Assert
                 (not Same_Id
                    (HRA_N.Core.Event.Id (Source.Events (I)),
                     HRA_N.Core.Event.Id (Replacement)));
               pragma Assert (False);
            end if;
            return;
         end if;
      end loop;
      pragma Assert (False);
   end Prove_Present_Not_Fresh;

   procedure Prove_Edge_Target_Substitution
     (Left, Right : Correction_Edge;
      Key         : Event_Id)
   with
     Ghost,
     Pre  => Left = Right and then not Same_Id (Left.Target, Key),
     Post => not Same_Id (Right.Target, Key);

   procedure Prove_Edge_Target_Substitution
     (Left, Right : Correction_Edge;
      Key         : Event_Id)
   is
   begin
      null;
   end Prove_Edge_Target_Substitution;

   procedure Prove_Not_Same_Through_Same
     (Left, Middle, Right : Event_Id)
   with
     Ghost,
     Pre  => Same_Id (Left, Middle) and then not Same_Id (Middle, Right),
     Post => not Same_Id (Left, Right);

   procedure Prove_Not_Same_Through_Same
     (Left, Middle, Right : Event_Id)
   is
   begin
      null;
   end Prove_Not_Same_Through_Same;

   procedure Prove_Frontier_Move
     (Source      : Correction_Image;
      Target_Id   : Event_Id;
      Replacement : HRA_N.Core.Event.Event;
      Result      : Correction_Image)
   with
     Ghost,
     Pre =>
       Correction_Shape_Admitted (Source)
       and then Current_In_Frontier (Source, Target_Id)
       and then Fresh_For (Source.Events, Replacement)
       and then
         One_Fresh_Append
           (Source.Events,
            Replacement,
            Result.Events.Snapshot,
            Result.Events)
       and then Result.Edge_Count = Source.Edge_Count + 1
       and then Edge_Prefix_Preserved (Source, Result)
       and then Same_Id
         (Result.Edges (Result.Edge_Count).Target, Target_Id)
       and then Same_Id
         (Result.Edges (Result.Edge_Count).Replacement,
          HRA_N.Core.Event.Id (Replacement)),
     Post =>
       not Current_In_Frontier (Result, Target_Id)
       and then
         Current_In_Frontier
           (Result, HRA_N.Core.Event.Id (Replacement));

   procedure Prove_Frontier_Move
     (Source      : Correction_Image;
      Target_Id   : Event_Id;
      Replacement : HRA_N.Core.Event.Event;
      Result      : Correction_Image)
   is
      Replacement_Id : constant Event_Id :=
        HRA_N.Core.Event.Id (Replacement);
      Target_Before : constant Lookup_Result :=
        Reference_Lookup (Source.Events, Target_Id);
      Target_After : constant Lookup_Result :=
        Reference_Lookup (Result.Events, Target_Id);
      Replacement_After : constant Lookup_Result :=
        Reference_Lookup (Result.Events, Replacement_Id);
   begin
      pragma Assert (Event_Present (Source, Target_Id));
      pragma Assert (Target_Before.State = Found);

      Prove_Prior_Lookup_Preserved
        (Source.Events,
         Replacement,
         Result.Events.Snapshot,
         Result.Events,
         Target_Id);

      pragma Assert (Target_After.State = Found);
      pragma Assert (Event_Present (Result, Target_Id));
      pragma Assert
        (Same_Id
           (Result.Edges (Result.Edge_Count).Target, Target_Id));
      pragma Assert (Is_Targeted (Result, Target_Id));
      pragma Assert (not Current_In_Frontier (Result, Target_Id));

      Prove_Added_Lookup
        (Source.Events,
         Replacement,
         Result.Events.Snapshot,
         Result.Events);

      pragma Assert (Replacement_After.State = Found);
      pragma Assert (Event_Present (Result, Replacement_Id));

      --  Freshness is a semantic separation fact: a retained source EventId
      --  cannot equal the fresh replacement identity.
      Prove_Present_Not_Fresh
        (Source.Events, Target_Id, Replacement);
      pragma Assert (not Same_Id (Target_Id, Replacement_Id));

      --  No old edge can target the fresh replacement: endpoint closure
      --  makes every old target a retained source Event, and freshness separates
      --  every retained source identity from Replacement.
      for I in 1 .. Source.Edge_Count loop
         pragma Loop_Invariant
           (for all J in 1 .. I - 1 =>
              not Same_Id (Result.Edges (J).Target, Replacement_Id));

         pragma Assert
           (Event_Present (Source, Source.Edges (I).Target));
         Prove_Present_Not_Fresh
           (Source.Events, Source.Edges (I).Target, Replacement);
         pragma Assert
           (not Same_Id (Source.Edges (I).Target, Replacement_Id));
         pragma Assert (Result.Edges (I) = Source.Edges (I));
         Prove_Edge_Target_Substitution
           (Source.Edges (I), Result.Edges (I), Replacement_Id);
         pragma Assert
           (not Same_Id (Result.Edges (I).Target, Replacement_Id));
      end loop;

      Prove_Not_Same_Through_Same
        (Result.Edges (Result.Edge_Count).Target,
         Target_Id,
         Replacement_Id);
      pragma Assert
        (not Same_Id
           (Result.Edges (Result.Edge_Count).Target, Replacement_Id));
      pragma Assert
        (for all I in 1 .. Result.Edge_Count =>
           not Same_Id (Result.Edges (I).Target, Replacement_Id));
      pragma Assert (not Is_Targeted (Result, Replacement_Id));
      pragma Assert (Current_In_Frontier (Result, Replacement_Id));
   end Prove_Frontier_Move;

   procedure Append_Current_Correction
     (Source          : Correction_Image;
      Target_Id       : Event_Id;
      Replacement     : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Result          : out Correction_Image;
      Status          : out Correction_Transition_Status)
   is
      Event_Status : Transition_Status;
   begin
      Result := Source;
      Result.Events.Snapshot := Target_Snapshot;

      if not Correction_Shape_Admitted (Source) then
         Status := Source_Shape_Invalid;
         return;
      elsif Source.Events.Count = Max_Events then
         Status := Source_Event_Full;
         return;
      elsif Source.Edge_Count = Max_Correction_Edges then
         Status := Source_Edge_Full;
         return;
      elsif not Current_In_Frontier (Source, Target_Id) then
         Status := Target_Not_Current;
         return;
      elsif not Fresh_For (Source.Events, Replacement) then
         Status := Duplicate_Replacement_Id;
         return;
      end if;

      Append_Fresh
        (Source.Events,
         Replacement,
         Target_Snapshot,
         Result.Events,
         Event_Status);

      pragma Assert (Event_Status = Transitioned);
      pragma Assert
        (One_Fresh_Append
           (Source.Events,
            Replacement,
            Target_Snapshot,
            Result.Events));

      Result.Edge_Count := Source.Edge_Count + 1;
      Result.Edges (Result.Edge_Count) :=
        (Target      => Target_Id,
         Replacement => HRA_N.Core.Event.Id (Replacement));

      Prove_Frontier_Move
        (Source, Target_Id, Replacement, Result);

      Status := Correction_Transitioned;
   end Append_Current_Correction;

end HRA_N.Core.Actual_Correction_Transition;
