-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Refinement
-------------------------------------------------------------------------------

with Ada.Containers;
with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Actual_Reader_Refinement;
use HRA_N.Core.Actual_Reader_Refinement;
with HRA_N.Core.Event;

package body HRA_N.Storage.Loam_Actual_Refinement is

   use type Ada.Containers.Count_Type;
   use type HRA_N.Core.Event.Event;
   use type HRA_N.Core.Event.Effect_List;

   Empty_Effects : constant HRA_N.Core.Event.Effect_List :=
     (Count => 0, Values => [others => HRA_N.Core.Event.Empty_Effect]);

   Empty_Event : constant HRA_N.Core.Event.Event :=
     HRA_N.Core.Event.Make_Event
       ((Token => (Length => 0, Value => [others => ' '])), Empty_Effects);

   function Reader_Result_Refines
     (Reader_Result : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Snapshot      : Snapshot_Id;
      Image         : Semantic_Image) return Boolean
   is
      Length : constant Ada.Containers.Count_Type :=
        Reader_Result.Events.Length;
   begin
      if not Reader_Result.Success
        or else Length > Ada.Containers.Count_Type (Max_Events)
        or else Image.Snapshot /= Snapshot
        or else Image.Count /= Natural (Length)
        or else not Event_Ids_Are_Unique (Image)
      then
         return False;
      end if;

      for I in 1 .. Image.Count loop
         if Image.Events (I) /= Reader_Result.Events.Element (Positive (I))
           or else not Same_Id
             (HRA_N.Core.Event.Id (Image.Events (I)),
              HRA_N.Core.Event.Id
                (Reader_Result.Events.Element (Positive (I))))
           or else HRA_N.Core.Event.Effects (Image.Events (I)) /=
             HRA_N.Core.Event.Effects
               (Reader_Result.Events.Element (Positive (I)))
         then
            return False;
         end if;
      end loop;
      return True;
   end Reader_Result_Refines;

   function To_Bounded_Semantic_Image
     (Reader_Result : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Snapshot      : Snapshot_Id) return Adapter_Result
   is
      Source : Production_Event_View :=
        (Reader_Succeeded => Reader_Result.Success,
         Count            => 0,
         Events           => [others => Empty_Event]);
      Image  : Semantic_Image;
      Status : Refinement_Status;
      Length : constant Ada.Containers.Count_Type :=
        Reader_Result.Events.Length;
   begin
      if not Reader_Result.Success then
         Refine_Reader_Events (Source, Snapshot, Image, Status);
         return (Status => Status, Image => Image);
      end if;

      if Length > Ada.Containers.Count_Type (Max_Events) then
         --  Preserve the fact that the source is over the bounded capacity;
         --  no prefix is copied or accepted as a successful refinement.
         Source.Count :=
           (if Length <= Ada.Containers.Count_Type (Max_Production_Events)
            then Production_Event_Count (Length)
            else Max_Production_Events);
         Refine_Reader_Events (Source, Snapshot, Image, Status);
         return (Status => Status, Image => Image);
      end if;

      Source.Count := Production_Event_Count (Length);
      for I in 1 .. Source.Count loop
         Source.Events (I) := Reader_Result.Events.Element (Positive (I));
      end loop;

      Refine_Reader_Events (Source, Snapshot, Image, Status);
      return (Status => Status, Image => Image);
   end To_Bounded_Semantic_Image;

end HRA_N.Storage.Loam_Actual_Refinement;
