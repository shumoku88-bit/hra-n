-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Reversal_Transition
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Reversal_Transition with
  SPARK_Mode => On
is
   use type HRA_N.Core.Event.Event;

   function Deterministic_Reversal_Id
     (Target_Id : Event_Id) return Event_Id
   is
      Text : constant String :=
        Reversal_Id_Prefix
        & Target_Id.Token.Value (1 .. Target_Id.Token.Length);
   begin
      return (Token => Make_Token (Text));
   end Deterministic_Reversal_Id;

   procedure Prove_Present_Not_Fresh
     (Source : Semantic_Image;
      Key    : Event_Id;
      Added  : HRA_N.Core.Event.Event)
   with
     Ghost,
     Pre =>
       (for some I in 1 .. Source.Count =>
          Same_Id (HRA_N.Core.Event.Id (Source.Events (I)), Key))
       and then Fresh_For (Source, Added),
     Post => not Same_Id (Key, HRA_N.Core.Event.Id (Added));

   procedure Prove_Present_Not_Fresh
     (Source : Semantic_Image;
      Key    : Event_Id;
      Added  : HRA_N.Core.Event.Event)
   is
   begin
      for I in 1 .. Source.Count loop
         if Same_Id (HRA_N.Core.Event.Id (Source.Events (I)), Key) then
            pragma Assert
              (not Same_Id
                 (HRA_N.Core.Event.Id (Source.Events (I)),
                  HRA_N.Core.Event.Id (Added)));
            if Same_Id (Key, HRA_N.Core.Event.Id (Added)) then
               pragma Assert
                 (Equal_Token
                    (HRA_N.Core.Event.Id (Source.Events (I)).Token,
                     Key.Token));
               pragma Assert
                 (Equal_Token
                    (Key.Token,
                     HRA_N.Core.Event.Id (Added).Token));
               pragma Assert
                 (Equal_Token
                    (HRA_N.Core.Event.Id (Source.Events (I)).Token,
                     HRA_N.Core.Event.Id (Added).Token));
               pragma Assert (False);
            end if;
            return;
         end if;
      end loop;
      pragma Assert (False);
   end Prove_Present_Not_Fresh;

   procedure Prove_Target_Preserved
     (Source       : Reversal_Image;
      Target_Id    : Event_Id;
      Target_Event : HRA_N.Core.Event.Event;
      Reversal     : HRA_N.Core.Event.Event;
      Result       : Reversal_Image)
   with
     Ghost,
     Pre =>
       Correction_Shape_Admitted (Source.Corrections)
       and then Current_In_Frontier (Source.Corrections, Target_Id)
       and then Target_Matches_Source (Source, Target_Id, Target_Event)
       and then
         One_Fresh_Append
           (Source.Corrections.Events,
            Reversal,
            Result.Corrections.Events.Snapshot,
            Result.Corrections.Events)
       and then Correction_Edges_Preserved (Source, Result),
     Post =>
       Current_In_Frontier (Result.Corrections, Target_Id)
       and then Target_Matches_Source (Result, Target_Id, Target_Event);

   procedure Prove_Target_Preserved
     (Source       : Reversal_Image;
      Target_Id    : Event_Id;
      Target_Event : HRA_N.Core.Event.Event;
      Reversal     : HRA_N.Core.Event.Event;
      Result       : Reversal_Image)
   is
      Before : constant Lookup_Result :=
        Reference_Lookup (Source.Corrections.Events, Target_Id);
      After : constant Lookup_Result :=
        Reference_Lookup (Result.Corrections.Events, Target_Id);
   begin
      pragma Assert (Before.State = Found);

      Prove_Prior_Lookup_Preserved
        (Source.Corrections.Events,
         Reversal,
         Result.Corrections.Events.Snapshot,
         Result.Corrections.Events,
         Target_Id);

      pragma Assert (After.State = Found);
      pragma Assert
        (HRA_N.Core.Actual_Correction_Transition.Event_Present
           (Result.Corrections, Target_Id));

      for I in 1 .. Result.Corrections.Edge_Count loop
         pragma Loop_Invariant
           (for all J in 1 .. I - 1 =>
              not Same_Id
                (Result.Corrections.Edges (J).Target, Target_Id));
         pragma Assert
           (Result.Corrections.Edges (I) =
              Source.Corrections.Edges (I));
         pragma Assert
           (not Same_Id
              (Source.Corrections.Edges (I).Target, Target_Id));
      end loop;

      pragma Assert
        (not Is_Targeted (Result.Corrections, Target_Id));
      pragma Assert
        (Current_In_Frontier (Result.Corrections, Target_Id));

      for I in 1 .. Source.Corrections.Events.Count loop
         if Same_Id
           (HRA_N.Core.Event.Id
              (Source.Corrections.Events.Events (I)),
            Target_Id)
         then
            pragma Assert
              (Source.Corrections.Events.Events (I) = Target_Event);
            pragma Assert
              (Result.Corrections.Events.Events (I) =
                 Source.Corrections.Events.Events (I));
            pragma Assert
              (Result.Corrections.Events.Events (I) = Target_Event);
            return;
         end if;
      end loop;
      pragma Assert (False);
   end Prove_Target_Preserved;

   procedure Prove_Result_Correction_Shape
     (Source   : Reversal_Image;
      Reversal : HRA_N.Core.Event.Event;
      Result   : Reversal_Image)
   with
     Ghost,
     Pre =>
       Correction_Shape_Admitted (Source.Corrections)
       and then
         One_Fresh_Append
           (Source.Corrections.Events,
            Reversal,
            Result.Corrections.Events.Snapshot,
            Result.Corrections.Events)
       and then Correction_Edges_Preserved (Source, Result),
     Post => Correction_Shape_Admitted (Result.Corrections);

   procedure Prove_Result_Correction_Shape
     (Source   : Reversal_Image;
      Reversal : HRA_N.Core.Event.Event;
      Result   : Reversal_Image)
   is
   begin
      pragma Assert
        (Event_Ids_Are_Unique (Result.Corrections.Events));

      for I in 1 .. Result.Corrections.Edge_Count loop
         pragma Assert
           (Result.Corrections.Edges (I) =
              Source.Corrections.Edges (I));
         pragma Assert
           (HRA_N.Core.Actual_Correction_Transition.Event_Present
              (Source.Corrections,
               Source.Corrections.Edges (I).Target));
         pragma Assert
           (HRA_N.Core.Actual_Correction_Transition.Event_Present
              (Source.Corrections,
               Source.Corrections.Edges (I).Replacement));

         declare
            Target_Before : constant Lookup_Result :=
              Reference_Lookup
                (Source.Corrections.Events,
                 Source.Corrections.Edges (I).Target);
            Replacement_Before : constant Lookup_Result :=
              Reference_Lookup
                (Source.Corrections.Events,
                 Source.Corrections.Edges (I).Replacement);
         begin
            pragma Assert (Target_Before.State = Found);
            pragma Assert (Replacement_Before.State = Found);
            Prove_Prior_Lookup_Preserved
              (Source.Corrections.Events,
               Reversal,
               Result.Corrections.Events.Snapshot,
               Result.Corrections.Events,
               Source.Corrections.Edges (I).Target);
            Prove_Prior_Lookup_Preserved
              (Source.Corrections.Events,
               Reversal,
               Result.Corrections.Events.Snapshot,
               Result.Corrections.Events,
               Source.Corrections.Edges (I).Replacement);
         end;

         pragma Assert
           (HRA_N.Core.Actual_Correction_Transition.Event_Present
              (Result.Corrections,
               Result.Corrections.Edges (I).Target));
         pragma Assert
           (HRA_N.Core.Actual_Correction_Transition.Event_Present
              (Result.Corrections,
               Result.Corrections.Edges (I).Replacement));
      end loop;

      pragma Assert (Edge_Endpoints_Are_Closed (Result.Corrections));

      for I in 1 .. Result.Corrections.Edge_Count loop
         for J in I + 1 .. Result.Corrections.Edge_Count loop
            pragma Assert
              (Result.Corrections.Edges (I) =
                 Source.Corrections.Edges (I));
            pragma Assert
              (Result.Corrections.Edges (J) =
                 Source.Corrections.Edges (J));
            pragma Assert
              (not Same_Id
                 (Source.Corrections.Edges (I).Target,
                  Source.Corrections.Edges (J).Target));
            pragma Assert
              (not Same_Id
                 (Source.Corrections.Edges (I).Replacement,
                  Source.Corrections.Edges (J).Replacement));
         end loop;
      end loop;

      pragma Assert (Targets_Are_Unique (Result.Corrections));
      pragma Assert (Replacements_Are_Unique (Result.Corrections));
   end Prove_Result_Correction_Shape;

   procedure Prove_Result_Reversal_Shape
     (Source       : Reversal_Image;
      Target_Id    : Event_Id;
      Target_Event : HRA_N.Core.Event.Event;
      Reversal     : HRA_N.Core.Event.Event;
      Result       : Reversal_Image)
   with
     Ghost,
     Pre =>
       Reversal_Shape_Admitted (Source)
       and then Current_In_Frontier (Source.Corrections, Target_Id)
       and then Target_Matches_Source (Source, Target_Id, Target_Event)
       and then not Is_Reversal_Endpoint (Source, Target_Id)
       and then Fresh_For (Source.Corrections.Events, Reversal)
       and then
         One_Fresh_Append
           (Source.Corrections.Events,
            Reversal,
            Result.Corrections.Events.Snapshot,
            Result.Corrections.Events)
       and then Correction_Edges_Preserved (Source, Result)
       and then Result.Edge_Count = Source.Edge_Count + 1
       and then Reversal_Edge_Prefix_Preserved (Source, Result)
       and then Same_Id
         (Result.Edges (Result.Edge_Count).Target, Target_Id)
       and then Same_Id
         (Result.Edges (Result.Edge_Count).Reversal,
          HRA_N.Core.Event.Id (Reversal)),
     Post => Reversal_Shape_Admitted (Result);

   procedure Prove_Result_Reversal_Shape
     (Source       : Reversal_Image;
      Target_Id    : Event_Id;
      Target_Event : HRA_N.Core.Event.Event;
      Reversal     : HRA_N.Core.Event.Event;
      Result       : Reversal_Image)
   is
   begin
      Prove_Result_Correction_Shape (Source, Reversal, Result);
      pragma Assert (Correction_Shape_Admitted (Result.Corrections));

      --  Old reversal endpoints remain closed because every old Event remains
      --  retained.  The new target is retained, and the new reversal is the
      --  freshly appended Event.
      for I in 1 .. Source.Edge_Count loop
         pragma Assert (Result.Edges (I) = Source.Edges (I));

         declare
            Target_Before : constant Lookup_Result :=
              Reference_Lookup
                (Source.Corrections.Events, Source.Edges (I).Target);
            Reversal_Before : constant Lookup_Result :=
              Reference_Lookup
                (Source.Corrections.Events, Source.Edges (I).Reversal);
         begin
            pragma Assert (Target_Before.State = Found);
            pragma Assert (Reversal_Before.State = Found);
            Prove_Prior_Lookup_Preserved
              (Source.Corrections.Events,
               Reversal,
               Result.Corrections.Events.Snapshot,
               Result.Corrections.Events,
               Source.Edges (I).Target);
            Prove_Prior_Lookup_Preserved
              (Source.Corrections.Events,
               Reversal,
               Result.Corrections.Events.Snapshot,
               Result.Corrections.Events,
               Source.Edges (I).Reversal);
         end;

         pragma Assert
           (Event_Present (Result, Result.Edges (I).Target));
         pragma Assert
           (Event_Present (Result, Result.Edges (I).Reversal));
      end loop;

      Prove_Target_Preserved
        (Source, Target_Id, Target_Event, Reversal, Result);
      pragma Assert (Event_Present (Result, Target_Id));

      Prove_Added_Lookup
        (Source.Corrections.Events,
         Reversal,
         Result.Corrections.Events.Snapshot,
         Result.Corrections.Events);
      pragma Assert
        (Event_Present (Result, HRA_N.Core.Event.Id (Reversal)));
      pragma Assert
        (Event_Present
           (Result, Result.Edges (Result.Edge_Count).Target));
      pragma Assert
        (Event_Present
           (Result, Result.Edges (Result.Edge_Count).Reversal));
      pragma Assert (Reversal_Endpoints_Are_Closed (Result));

      --  Freshness separates the new reversal identity from every retained old
      --  endpoint.  The selected target was not an old reversal endpoint.
      Prove_Present_Not_Fresh
        (Source.Corrections.Events, Target_Id, Reversal);
      pragma Assert
        (not Same_Id (Target_Id, HRA_N.Core.Event.Id (Reversal)));

      for I in 1 .. Source.Edge_Count loop
         pragma Loop_Invariant
           (for all J in 1 .. I - 1 =>
              not Same_Id
                (Result.Edges (J).Target, Target_Id)
              and then not Same_Id
                (Result.Edges (J).Reversal, Target_Id)
              and then not Same_Id
                (Result.Edges (J).Target,
                 HRA_N.Core.Event.Id (Reversal))
              and then not Same_Id
                (Result.Edges (J).Reversal,
                 HRA_N.Core.Event.Id (Reversal)));

         pragma Assert (Result.Edges (I) = Source.Edges (I));
         pragma Assert
           (not Same_Id (Source.Edges (I).Target, Target_Id));
         pragma Assert
           (not Same_Id (Source.Edges (I).Reversal, Target_Id));

         pragma Assert
           (Event_Present (Source, Source.Edges (I).Target));
         pragma Assert
           (Event_Present (Source, Source.Edges (I).Reversal));
         Prove_Present_Not_Fresh
           (Source.Corrections.Events,
            Source.Edges (I).Target,
            Reversal);
         Prove_Present_Not_Fresh
           (Source.Corrections.Events,
            Source.Edges (I).Reversal,
            Reversal);
      end loop;

      for I in 1 .. Result.Edge_Count loop
         for J in I + 1 .. Result.Edge_Count loop
            if J <= Source.Edge_Count then
               pragma Assert (I <= Source.Edge_Count);
               pragma Assert (Result.Edges (I) = Source.Edges (I));
               pragma Assert (Result.Edges (J) = Source.Edges (J));
            else
               pragma Assert (J = Result.Edge_Count);
               pragma Assert (I <= Source.Edge_Count);
               pragma Assert (Result.Edges (I) = Source.Edges (I));
               pragma Assert
                 (not Same_Id
                    (Result.Edges (I).Target,
                     Result.Edges (J).Target));
               pragma Assert
                 (not Same_Id
                    (Result.Edges (I).Reversal,
                     Result.Edges (J).Target));
               pragma Assert
                 (not Same_Id
                    (Result.Edges (I).Target,
                     Result.Edges (J).Reversal));
               pragma Assert
                 (not Same_Id
                    (Result.Edges (I).Reversal,
                     Result.Edges (J).Reversal));
            end if;
         end loop;
      end loop;

      pragma Assert
        (not Same_Id
           (Result.Edges (Result.Edge_Count).Target,
            Result.Edges (Result.Edge_Count).Reversal));
      pragma Assert (Reversal_Endpoints_Are_Unique (Result));
   end Prove_Result_Reversal_Shape;

   procedure Append_Current_Reversal
     (Source          : Reversal_Image;
      Target_Id       : Event_Id;
      Target_Event    : HRA_N.Core.Event.Event;
      Reversal        : HRA_N.Core.Event.Event;
      Target_Snapshot : Snapshot_Id;
      Result          : out Reversal_Image;
      Status          : out Reversal_Transition_Status)
   is
      Event_Status : Transition_Status;
   begin
      Result := Source;
      Result.Corrections.Events.Snapshot := Target_Snapshot;

      if not Reversal_Shape_Admitted (Source) then
         Status := Source_Shape_Invalid;
         return;
      elsif Source.Corrections.Events.Count = Max_Events then
         Status := Source_Event_Full;
         return;
      elsif Source.Edge_Count = Max_Reversal_Edges then
         Status := Source_Reversal_Full;
         return;
      elsif not Current_In_Frontier (Source.Corrections, Target_Id) then
         Status := Target_Not_Current;
         return;
      elsif not Target_Matches_Source (Source, Target_Id, Target_Event) then
         Status := Target_Event_Mismatch;
         return;
      elsif Is_Reversal_Endpoint (Source, Target_Id) then
         Status := Target_Already_In_Reversal;
         return;
      elsif not Reversal_Id_Fits (Target_Id) then
         Status := Reversal_Id_Too_Long;
         return;
      elsif not Same_Id
        (HRA_N.Core.Event.Id (Reversal),
         Deterministic_Reversal_Id (Target_Id))
      then
         Status := Wrong_Reversal_Id;
         return;
      elsif not Fresh_For (Source.Corrections.Events, Reversal) then
         Status := Duplicate_Reversal_Id;
         return;
      elsif not Writer_Inverse_Of (Target_Event, Reversal) then
         Status := Reversal_Not_Exact_Inverse;
         return;
      end if;

      Append_Fresh
        (Source.Corrections.Events,
         Reversal,
         Target_Snapshot,
         Result.Corrections.Events,
         Event_Status);

      pragma Assert (Event_Status = Transitioned);
      pragma Assert
        (One_Fresh_Append
           (Source.Corrections.Events,
            Reversal,
            Target_Snapshot,
            Result.Corrections.Events));
      pragma Assert (Correction_Edges_Preserved (Source, Result));

      Result.Edge_Count := Source.Edge_Count + 1;
      Result.Edges (Result.Edge_Count) :=
        (Target   => Target_Id,
         Reversal => HRA_N.Core.Event.Id (Reversal));

      pragma Assert (Reversal_Edge_Prefix_Preserved (Source, Result));

      Prove_Target_Preserved
        (Source, Target_Id, Target_Event, Reversal, Result);

      Prove_Result_Reversal_Shape
        (Source,
         Target_Id,
         Target_Event,
         Reversal,
         Result);

      Status := Reversal_Transitioned;
   end Append_Current_Reversal;

end HRA_N.Core.Actual_Reversal_Transition;
