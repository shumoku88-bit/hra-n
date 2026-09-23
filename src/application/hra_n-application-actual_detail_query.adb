with Ada.Directories;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Loam_Actual_Replay_Snapshot;

package body HRA_N.Application.Actual_Detail_Query is

   package Bound_Replay renames
     HRA_N.Storage.Loam_Actual_Replay_Snapshot;

   use type Bound_Replay.Snapshot_Open_Status;
   use type Bound_Replay.Replay_Status;

   function Execute
     (Paths    : HRA_N.Application.Path_Resolver.Path_Config;
      Event_Id : Token_Text) return Actual_Detail_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;

      Result  : Actual_Detail_View;

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         Result.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;

   begin
      Result.Event_Id := Event_Id;

      if not Paths.Resolution_Ok then
         Set_Diagnostic (Paths.Error_Reason (1 .. Paths.Error_Len));
         return Result;
      end if;

      if Canonical_Authority_Present (Data_Dir_Str (Paths)) then
         declare
            Canonical_Path : constant String :=
              Ada.Directories.Compose
                (Data_Dir_Str (Paths), "actual.loam");
         begin
            return Execute_Loam_Actual (Canonical_Path, Event_Id);
         end;
      end if;

      if Paths.Is_Versioned then
         Result.Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      declare
         Journal : constant Journal_Result :=
           Read_Journal_File (Journal_Path_Str (Paths));
      begin
         if not Journal.Success then
            Set_Diagnostic
              ("journal.hra: " &
               Journal.Error_Reason (1 .. Journal.Error_Len));
            return Result;
         end if;

         for Item of Journal.Events loop
            if Equal_Token (Id (Item).Token, Event_Id) then
               Find_Occurrence_Date
                 (Journal.Validities,
                  Id (Item),
                  Result.Valid_On,
                  Result.Has_Date);

               declare
                  Has_Description : Boolean;
               begin
                  Find_Description
                    (Journal.Descriptions,
                     Id (Item),
                     Result.Description,
                     Has_Description);
                  if not Has_Description then
                     Result.Description :=
                       (Length => 0, Value => [others => ' ']);
                  end if;
               end;

               declare
                  Metadata : Transaction_Metadata_Entry;
                  Found    : Boolean;
               begin
                  Find_Metadata (Journal.Metadata, Id (Item), Metadata, Found);
                  if Found then
                     Result.Has_Purpose := Metadata.Purpose.Present;
                     Result.Purpose := Metadata.Purpose.Value;
                     Result.Has_Replaces := Metadata.Replaces.Present;
                     Result.Replaces := Metadata.Replaces.Value.Token;
                     Result.Has_Reverses := Metadata.Reverses.Present;
                     Result.Reverses := Metadata.Reverses.Value.Token;
                     Result.Has_Relation := Metadata.Relation.Present;
                     Result.Relation := Metadata.Relation.Value;
                     Result.Has_Discharge := Metadata.Discharge.Present;
                     Result.Discharge := Metadata.Discharge.Value;
                  end if;
               end;

               declare
                  Successor  : HRA_N.Core.Types.Event_Id;
                  Succ_Found : Boolean;
               begin
                  Find_Successor
                    (Journal.Metadata,
                     Id (Item),
                     Successor,
                     Succ_Found);
                  Result.Is_Superseded := Succ_Found;
                  if Succ_Found then
                     Result.Superseded_By := Successor.Token;
                  end if;
               end;

               declare
                  Reversal   : HRA_N.Core.Types.Event_Id;
                  Rev_Found  : Boolean;
               begin
                  Find_Reverser
                    (Journal.Metadata,
                     Id (Item),
                     Reversal,
                     Rev_Found);
                  Result.Is_Reversed := Rev_Found;
                  if Rev_Found then
                     Result.Reversed_By := Reversal.Token;
                  end if;
               end;

               Result.Links :=
                 HRA_N.Application.Relation_Query.Links_For_Event
                   (Paths, Id (Item).Token);
               Result.Effect_Count := Effect_Count (Item);
               for Index in 1 .. Effect_Count (Item) loop
                  declare
                     Item_Effect : constant Effect := Effect_At (Item, Index);
                  begin
                     Result.Effects (Index) :=
                       (Locus   => Item_Effect.Locus.Token,
                        Measure => Item_Effect.Measure.Token,
                        Amount  => Item_Effect.Amount.Quanta);
                  end;
               end loop;

               if Result.Has_Date then
                  Result.Status := Query_Complete;
               else
                  Result.Status := Query_Partial;
                  Set_Diagnostic ("Actual record has no occurrence date");
               end if;
               return Result;
            end if;
         end loop;

         Set_Diagnostic ("selected Actual identity is absent from current journal");
         return Result;
      end;
   end Execute;

   function Execute_Loam_Actual
     (Path     : String;
      Event_Id : Token_Text) return Actual_Detail_View
   is
      use HRA_N.Application.Frontend_Types;

      Result      : Actual_Detail_View;
      Snapshot    : Bound_Replay.Replay_Snapshot;
      Open_Status : Bound_Replay.Snapshot_Open_Status;
      Key         : constant HRA_N.Core.Types.Event_Id :=
        (Token => Event_Id);

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic := [others => ' '];
         Result.Diagnostic_Len := Len;
         if Len > 0 then
            Result.Diagnostic (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
      end Set_Diagnostic;

      procedure Close_Snapshot is
      begin
         Bound_Replay.Close (Snapshot);
      exception
         when others =>
            null;
      end Close_Snapshot;

   begin
      Result.Event_Id := Event_Id;
      Bound_Replay.Open (Snapshot, Path, Open_Status);

      if Open_Status /= Bound_Replay.Snapshot_Opened then
         case Open_Status is
            when Bound_Replay.Snapshot_Admission_Failed =>
               Set_Diagnostic ("actual.loam failed semantic admission");
            when Bound_Replay.Snapshot_Locate_Failed
               | Bound_Replay.Snapshot_Duplicate_Event_Id
               | Bound_Replay.Snapshot_Correspondence_Failed =>
               Set_Diagnostic ("actual.loam replay snapshot correspondence failed");
            when others =>
               Set_Diagnostic ("actual.loam replay snapshot could not open");
         end case;
         Close_Snapshot;
         return Result;
      end if;

      declare
         Replayed : constant Bound_Replay.Replay_Result :=
           Bound_Replay.Replay_Event (Snapshot, Key);
      begin
         if Replayed.Status = Bound_Replay.Replay_Event_Not_Found then
            Set_Diagnostic
              ("selected Actual identity is absent from current actual.loam");
            Close_Snapshot;
            return Result;
         elsif Replayed.Status /= Bound_Replay.Replay_Succeeded
           or else not Replayed.Decoded.Success
         then
            Set_Diagnostic ("actual.loam snapshot-bound Event replay failed");
            Close_Snapshot;
            return Result;
         end if;

         declare
            Context : constant Bound_Replay.Admitted_Context_Result :=
              Bound_Replay.Admitted_Context_For (Snapshot, Key);
            Item : constant Event := Replayed.Decoded.Value;
         begin
            if not Context.Present then
               Set_Diagnostic
                 ("actual.loam admitted context unavailable for replayed Event");
               Close_Snapshot;
               return Result;
            end if;

            Result.Has_Date := Context.Has_Date;
            Result.Valid_On := Context.Valid_On;
            if Context.Has_Description then
               Result.Description := Context.Description;
            else
               Result.Description :=
                 (Length => 0, Value => [others => ' ']);
            end if;

            if Context.Metadata_Found then
               Result.Has_Purpose := Context.Metadata.Purpose.Present;
               Result.Purpose := Context.Metadata.Purpose.Value;
               Result.Has_Replaces := Context.Metadata.Replaces.Present;
               Result.Replaces := Context.Metadata.Replaces.Value.Token;
               Result.Has_Reverses := Context.Metadata.Reverses.Present;
               Result.Reverses := Context.Metadata.Reverses.Value.Token;
               Result.Has_Relation := Context.Metadata.Relation.Present;
               Result.Relation := Context.Metadata.Relation.Value;
               Result.Has_Discharge := Context.Metadata.Discharge.Present;
               Result.Discharge := Context.Metadata.Discharge.Value;
            end if;

            Result.Is_Superseded := Context.Has_Successor;
            if Context.Has_Successor then
               Result.Superseded_By := Context.Successor.Token;
            end if;

            Result.Is_Reversed := Context.Has_Reverser;
            if Context.Has_Reverser then
               Result.Reversed_By := Context.Reverser.Token;
            end if;

            --  Relation links still belong to the transitional journal
            --  authority.  Do not combine that authority with this Loam
            --  snapshot-bound query; Links therefore remains unavailable.
            Result.Links.Success := False;

            Result.Effect_Count := Effect_Count (Item);
            for Index in 1 .. Effect_Count (Item) loop
               declare
                  Item_Effect : constant Effect := Effect_At (Item, Index);
               begin
                  Result.Effects (Index) :=
                    (Locus   => Item_Effect.Locus.Token,
                     Measure => Item_Effect.Measure.Token,
                     Amount  => Item_Effect.Amount.Quanta);
               end;
            end loop;

            if Result.Has_Date then
               Result.Status := Query_Complete;
            else
               Result.Status := Query_Partial;
               Set_Diagnostic ("Actual record has no occurrence date");
            end if;
         end;
      end;

      Close_Snapshot;
      return Result;

   exception
      when others =>
         Close_Snapshot;
         Set_Diagnostic ("unexpected actual.loam detail replay failure");
         return Result;
   end Execute_Loam_Actual;

end HRA_N.Application.Actual_Detail_Query;
