-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Actual_Writer_Transition
-------------------------------------------------------------------------------

package body HRA_N.Core.Actual_Writer_Transition with
  SPARK_Mode => On
is

   procedure Prove_Unique_Position
     (Image : Semantic_Image;
      Key   : Event_Id;
      Left  : Event_Position;
      Right : Event_Position)
   with
     Ghost,
     Pre =>
       Event_Ids_Are_Unique (Image)
       and then Left <= Image.Count
       and then Right <= Image.Count
       and then Same_Id (Id (Image.Events (Left)), Key)
       and then Same_Id (Id (Image.Events (Right)), Key),
     Post => Left = Right;

   procedure Prove_Unique_Position
     (Image : Semantic_Image;
      Key   : Event_Id;
      Left  : Event_Position;
      Right : Event_Position)
   is
   begin
      if Left < Right then
         pragma Assert
           (not Same_Id
              (Id (Image.Events (Left)),
               Id (Image.Events (Right))));
         pragma Assert (False);
      elsif Right < Left then
         pragma Assert
           (not Same_Id
              (Id (Image.Events (Right)),
               Id (Image.Events (Left))));
         pragma Assert (False);
      end if;
   end Prove_Unique_Position;

   procedure Prove_Target_Unique
     (Source : Semantic_Image;
      Added  : Event;
      Target : Semantic_Image)
   with
     Ghost,
     Pre =>
       Event_Ids_Are_Unique (Source)
       and then Source.Count < Max_Events
       and then Fresh_For (Source, Added)
       and then Target.Count = Source.Count + 1
       and then Prefix_Preserved (Source, Target)
       and then Target.Events (Target.Count) = Added,
     Post => Event_Ids_Are_Unique (Target);

   procedure Prove_Target_Unique
     (Source : Semantic_Image;
      Added  : Event;
      Target : Semantic_Image)
   is
   begin
      for I in 1 .. Target.Count loop
         for J in I + 1 .. Target.Count loop
            if J <= Source.Count then
               pragma Assert (I <= Source.Count);
               pragma Assert
                 (Target.Events (I) = Source.Events (I));
               pragma Assert
                 (Target.Events (J) = Source.Events (J));
               pragma Assert
                 (not Same_Id
                    (Id (Source.Events (I)),
                     Id (Source.Events (J))));
               pragma Assert
                 (not Same_Id
                    (Id (Target.Events (I)),
                     Id (Target.Events (J))));
            else
               pragma Assert (J = Target.Count);
               pragma Assert (I <= Source.Count);
               pragma Assert
                 (Target.Events (I) = Source.Events (I));
               pragma Assert (Target.Events (J) = Added);
               pragma Assert
                 (not Same_Id
                    (Id (Source.Events (I)),
                     Id (Added)));
               pragma Assert
                 (not Same_Id
                    (Id (Target.Events (I)),
                     Id (Target.Events (J))));
            end if;
         end loop;
      end loop;
   end Prove_Target_Unique;

   procedure Append_Fresh
     (Source          : Semantic_Image;
      Added           : Event;
      Target_Snapshot : Snapshot_Id;
      Target          : out Semantic_Image;
      Status          : out Transition_Status)
   is
   begin
      Target :=
        (Snapshot => Target_Snapshot,
         Count    => Source.Count,
         Events   => Source.Events);

      if not Event_Ids_Are_Unique (Source) then
         Status := Source_Not_Unique;
         return;
      elsif Source.Count = Max_Events then
         Status := Source_Full;
         return;
      elsif not Fresh_For (Source, Added) then
         Status := Duplicate_Event_Id;
         return;
      end if;

      Target.Count := Source.Count + 1;
      Target.Events (Target.Count) := Added;

      Prove_Target_Unique (Source, Added, Target);
      Status := Transitioned;
   end Append_Fresh;

   procedure Prove_Added_Lookup
     (Source          : Semantic_Image;
      Added           : Event;
      Target_Snapshot : Snapshot_Id;
      Target          : Semantic_Image)
   is
      pragma Unreferenced (Source, Target_Snapshot);
      Result : constant Lookup_Result :=
        Reference_Lookup (Target, Id (Added));
   begin
      pragma Assert (Target.Count > 0);
      pragma Assert (Target.Events (Target.Count) = Added);
      pragma Assert
        (Same_Id
           (Id (Target.Events (Target.Count)),
            Id (Added)));
      pragma Assert (Result.State = Found);

      Prove_Unique_Position
        (Target,
         Id (Added),
         Result.Position,
         Event_Position (Target.Count));

      pragma Assert (Result.Position = Target.Count);
      pragma Assert
        (Result.Value = Target.Events (Result.Position));
      pragma Assert (Result.Value = Added);
   end Prove_Added_Lookup;

   procedure Prove_Prior_Lookup_Preserved
     (Source          : Semantic_Image;
      Added           : Event;
      Target_Snapshot : Snapshot_Id;
      Target          : Semantic_Image;
      Key             : Event_Id)
   is
      pragma Unreferenced (Added, Target_Snapshot);
      Before : constant Lookup_Result :=
        Reference_Lookup (Source, Key);
      After : constant Lookup_Result :=
        Reference_Lookup (Target, Key);
   begin
      pragma Assert (Before.State = Found);
      pragma Assert (Before.Position <= Source.Count);
      pragma Assert
        (Before.Value = Source.Events (Before.Position));
      pragma Assert
        (Target.Events (Before.Position) =
           Source.Events (Before.Position));
      pragma Assert
        (Same_Id
           (Id (Target.Events (Before.Position)), Key));
      pragma Assert (After.State = Found);

      Prove_Unique_Position
        (Target,
         Key,
         After.Position,
         Before.Position);

      pragma Assert (After.Position = Before.Position);
      pragma Assert
        (After.Value = Target.Events (After.Position));
      pragma Assert
        (After.Value = Before.Value);
      pragma Assert (After = Before);
   end Prove_Prior_Lookup_Preserved;

end HRA_N.Core.Actual_Writer_Transition;
