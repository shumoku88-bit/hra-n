with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;

package body HRA_N.Application.Actual_Detail_Query is

   function Execute
     (Paths    : HRA_N.Application.Path_Resolver.Path_Config;
      Event_Id : Token_Text) return Actual_Detail_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;

      Result  : Actual_Detail_View;
      Journal : constant Journal_Result :=
        Read_Journal_File (Journal_Path_Str (Paths));

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
      elsif Paths.Is_Versioned then
         Result.Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

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
   end Execute;

end HRA_N.Application.Actual_Detail_Query;
