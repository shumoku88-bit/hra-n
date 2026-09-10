-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Correction_Publisher
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Streams; with Ada.Streams.Stream_IO;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Core.Actual_Reversal; use HRA_N.Core.Actual_Reversal;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Validity_Reader; use HRA_N.Storage.Validity_Reader;
with HRA_N.Storage.Description_Reader; use HRA_N.Storage.Description_Reader;
with HRA_N.Storage.Locus_Reader; use HRA_N.Storage.Locus_Reader;
with HRA_N.Storage.Relation_Reader; use HRA_N.Storage.Relation_Reader;
with HRA_N.Storage.Actual_Reversal_Reader; use HRA_N.Storage.Actual_Reversal_Reader;
with HRA_N.Storage.Correction;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Application.Correction_Frontier; use HRA_N.Application.Correction_Frontier;
with HRA_N.Application.Authority_Transaction; use HRA_N.Application.Authority_Transaction;

package body HRA_N.Application.Correction_Publisher is

   function Natural_Image (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Natural_Image;

   function Quanta_Image (Q : Quanta_Type) return String is
      Img : constant String := Quanta_Type'Image (Q);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Quanta_Image;

   function Escape_Text (S : String) return String is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      for I in S'Range loop
         case S (I) is
            when '\' =>
               Append (Result, "\\");
            when ASCII.LF =>
               Append (Result, "\n");
            when ASCII.CR =>
               Append (Result, "\r");
            when ASCII.HT =>
               Append (Result, "\t");
            when others =>
               Append (Result, S (I));
         end case;
      end loop;
      return To_String (Result);
   end Escape_Text;

   function Read_All (Path : String) return Unbounded_String is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
      use type SIO.Count;
   begin
      if not Ada.Directories.Exists (Path) then
         return Null_Unbounded_String;
      end if;
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         if Size = 0 then
            SIO.Close (File);
            return Null_Unbounded_String;
         end if;
         SIO.Read (File, Data, Last);
         SIO.Close (File);
         declare
            Text : String (1 .. Natural (Last));
            for Text'Address use Data'Address;
         begin
            return To_Unbounded_String (Text);
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return Null_Unbounded_String;
   end Read_All;

   function Set_Error
     (Receipt : in out Correction_Receipt;
      Msg     : String) return Correction_Receipt
   is
      Len : constant Natural := Natural'Min (Msg'Length, Receipt.Error_Reason'Length);
   begin
      Receipt.Success := False;
      Receipt.Error_Len := Len;
      Receipt.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Receipt;
   end Set_Error;

   function Make_Two_Party_Draft
     (Target      : String;
      From_Locus  : String;
      To_Locus    : String;
      Amount      : Quanta_Type;
      Description : String := "") return Correction_Draft
   is
      Draft : Correction_Draft;
   begin
      Draft.Target := (Token => Make_Token (Target));
      Draft.Effects.Count := 2;
      Draft.Effects.Values (1) :=
        (Key     => (Token => Make_Token ("effect-1")),
         Locus   => (Token => Make_Token (From_Locus)),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => -Amount));
      Draft.Effects.Values (2) :=
        (Key     => (Token => Make_Token ("effect-2")),
         Locus   => (Token => Make_Token (To_Locus)),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => Amount));
      if Description'Length > 0 then
         Draft.Description := To_Unbounded_String (Description);
      end if;
      return Draft;
   end Make_Two_Party_Draft;

   function Movement_Effects_Valid (Effects : Effect_List) return Boolean is
      Sum : Long_Long_Integer := 0;
   begin
      if Effects.Count = 0 then
         return False;
      end if;
      if not Keys_Are_Unique (Effects) then
         return False;
      end if;
      for I in 1 .. Effects.Count loop
         declare
            Eff : constant Effect := Effects.Values (I);
         begin
            if Eff.Key.Token.Length = 0
              or else Eff.Locus.Token.Length = 0
              or else not Equal_Token (Eff.Measure.Token, Make_Token ("jpy"))
              or else Eff.Amount.Quanta = 0
            then
               return False;
            end if;
            Sum := Sum + Long_Long_Integer (Eff.Amount.Quanta);
         end;
      end loop;
      return Sum = 0;
   end Movement_Effects_Valid;

   function Loci_Admitted
     (Vocab   : Locus_Vocabulary;
      Effects : Effect_List) return Boolean
   is
   begin
      for I in 1 .. Effects.Count loop
         if not Admits_Locus (Vocab, Effects.Values (I).Locus) then
            return False;
         end if;
      end loop;
      return True;
   end Loci_Admitted;

   function Find_Target_Event
     (Events : Event_Vectors.Vector;
      Target : Event_Id;
      Ev     : out Event) return Boolean
   is
   begin
      for E of Events loop
         if Equal_Token (Id (E).Token, Target.Token) then
            Ev := E;
            return True;
         end if;
      end loop;
      return False;
   end Find_Target_Event;

   function Relations_Mention_Event
     (Units      : Unit_Memory;
      Discharges : Discharge_Memory;
      Id         : Event_Id) return Boolean
   is
   begin
      for I in 1 .. Units.Count loop
         if Equal_Token (Units.Units (I).Source_Event.Token, Id.Token) then
            return True;
         end if;
      end loop;
      for I in 1 .. Discharges.Count loop
         if Equal_Token (Discharges.Discharges (I).Event.Token, Id.Token) then
            return True;
         end if;
      end loop;
      return False;
   end Relations_Mention_Event;

   function Reversals_Mention_Event
     (Reversals : Reversal_Memory;
      Id        : Event_Id) return Boolean
   is
   begin
      for I in 1 .. Reversals.Count loop
         if Equal_Token (Reversals.Entries (I).Target.Token, Id.Token)
           or else Equal_Token (Reversals.Entries (I).Reversal.Token, Id.Token)
         then
            return True;
         end if;
      end loop;
      return False;
   end Reversals_Mention_Event;

   function Corrections_Mention_Event
     (Corrections : Correction_Memory;
      Id          : Event_Id) return Boolean
   is
   begin
      for I in 1 .. Corrections.Count loop
         if Equal_Token (Corrections.Values (I).Target.Token, Id.Token)
           or else Equal_Token (Corrections.Values (I).Replacement.Token, Id.Token)
         then
            return True;
         end if;
      end loop;
      return False;
   end Corrections_Mention_Event;

   function Descriptions_Mention_Event
     (Desc : Description_Memory;
      Id   : Event_Id) return Boolean
   is
      Text  : Description_Text;
      Found : Boolean;
   begin
      Find_Description (Desc, Id, Text, Found);
      return Found;
   end Descriptions_Mention_Event;

   function Validity_Mentions_Event
     (Val : Validity_Memory;
      Id  : Event_Id) return Boolean
   is
      D     : Date_Type;
      Found : Boolean;
   begin
      Find_Occurrence_Date (Val, Id, D, Found);
      return Found;
   end Validity_Mentions_Event;

   function Events_Mention_Event
     (Events : Event_Vectors.Vector;
      Id     : Event_Id) return Boolean
   is
   begin
      for Ev of Events loop
         if Equal_Token (HRA_N.Core.Event.Id (Ev).Token, Id.Token) then
            return True;
         end if;
      end loop;
      return False;
   end Events_Mention_Event;

   function Event_Identity_Reserved
     (Events      : Event_Vectors.Vector;
      Val         : Validity_Memory;
      Desc        : Description_Memory;
      Units       : Unit_Memory;
      Discharges  : Discharge_Memory;
      Corrections : Correction_Memory;
      Reversals   : Reversal_Memory;
      Id          : Event_Id) return Boolean
   is
     (Events_Mention_Event (Events, Id)
      or else Validity_Mentions_Event (Val, Id)
      or else Descriptions_Mention_Event (Desc, Id)
      or else Relations_Mention_Event (Units, Discharges, Id)
      or else Corrections_Mention_Event (Corrections, Id)
      or else Reversals_Mention_Event (Reversals, Id));

   function Fresh_Replacement_Id
     (Events      : Event_Vectors.Vector;
      Val         : Validity_Memory;
      Desc        : Description_Memory;
      Units       : Unit_Memory;
      Discharges  : Discharge_Memory;
      Corrections : Correction_Memory;
      Reversals   : Reversal_Memory) return Event_Id
   is
      Limit : constant Positive :=
        Natural (Events.Length) + Entry_Count (Val) + 1000;
   begin
      for I in 1 .. Limit loop
         declare
            Candidate : constant String := "replacement-" & Natural_Image (I);
            Cand_Id   : constant Event_Id := (Token => Make_Token (Candidate));
         begin
            if not Event_Identity_Reserved
              (Events      => Events,
               Val         => Val,
               Desc        => Desc,
               Units       => Units,
               Discharges  => Discharges,
               Corrections => Corrections,
               Reversals   => Reversals,
               Id          => Cand_Id)
            then
               return Cand_Id;
            end if;
         end;
      end loop;
      return (Token => (Length => 0, Value => [others => ' ']));
   end Fresh_Replacement_Id;

   function Fresh_Correction_Id
     (Corrections : Correction_Memory) return Correction_Id
   is
   begin
      for I in 1 .. Corrections.Count + 1000 loop
         declare
            Candidate : constant String := "correction-" & Natural_Image (I);
            Cand_Tok  : constant Token_Text := Make_Token (Candidate);
            Found     : Boolean := False;
         begin
            for J in 1 .. Corrections.Count loop
               if Equal_Token (Corrections.Values (J).Id.Token, Cand_Tok) then
                  Found := True;
                  exit;
               end if;
            end loop;
            if not Found then
               return (Token => Cand_Tok);
            end if;
         end;
      end loop;
      return (Token => (Length => 0, Value => [others => ' ']));
   end Fresh_Correction_Id;

   function Format_Event_Append
     (Ev_Id   : Event_Id;
      Effects : Effect_List) return String
   is
      Result  : Unbounded_String := Null_Unbounded_String;
      Id_Str  : constant String := Ev_Id.Token.Value (1 .. Ev_Id.Token.Length);
   begin
      Append (Result, "EVENT" & ASCII.HT & Id_Str & ASCII.LF);
      for I in 1 .. Effects.Count loop
         declare
            Eff      : constant Effect := Effects.Values (I);
            Key_Str  : constant String := Eff.Key.Token.Value (1 .. Eff.Key.Token.Length);
            Loc_Str  : constant String := Eff.Locus.Token.Value (1 .. Eff.Locus.Token.Length);
            Meas_Str : constant String := Eff.Measure.Token.Value (1 .. Eff.Measure.Token.Length);
            Amt_Str  : constant String := Quanta_Image (Eff.Amount.Quanta);
         begin
            Append (Result, "EFFECT" & ASCII.HT & Key_Str & ASCII.HT &
                    Loc_Str & ASCII.HT & Meas_Str & ASCII.HT & Amt_Str & ASCII.LF);
         end;
      end loop;
      return To_String (Result);
   end Format_Event_Append;

   function Publish_Correction
     (Authority_Dir   : String;
      Correction_Path : String;
      Reversals_Path  : String;
      Draft           : Correction_Draft;
      Fault           : Correction_Fault := Correction_Fault_None) return Correction_Receipt
   is
      Receipt : Correction_Receipt;
      Tx      : Transaction;
      Err     : String (1 .. 256) := [others => ' '];
      Err_Len : Natural           := 0;
   begin
      --  1. Preflight draft validation
      if Draft.Target.Token.Length = 0 then
         return Set_Error (Receipt, "loam: selected correction target is not retained");
      end if;

      if not Movement_Effects_Valid (Draft.Effects) then
         return Set_Error
           (Receipt, "loam: correction replacement must be one balanced nonzero JPY Movement");
      end if;

      --  2. Acquire writer ownership lock and verify CURRENT snapshot
      if not Open_Transaction (Authority_Dir, Tx, Err, Err_Len) then
         return Set_Error (Receipt, Err (1 .. Err_Len));
      end if;

      declare
         Manifest : constant Manifest_Record := Snapshot_Manifest (Tx);

         Event_Full     : constant String := Authority_Dir & "/" &
           Manifest (Family_Event).Rel_Path (1 .. Manifest (Family_Event).Path_Len);
         Val_Full       : constant String := Authority_Dir & "/" &
           Manifest (Family_Actual_Validity).Rel_Path (1 .. Manifest (Family_Actual_Validity).Path_Len);
         Desc_Full      : constant String := Authority_Dir & "/" &
           Manifest (Family_Event_Description).Rel_Path (1 .. Manifest (Family_Event_Description).Path_Len);
         Locus_Full     : constant String := Authority_Dir & "/" &
           Manifest (Family_Locus_Admission).Rel_Path (1 .. Manifest (Family_Locus_Admission).Path_Len);
         Unit_Full      : constant String := Authority_Dir & "/" &
           Manifest (Family_Relation_Unit).Rel_Path (1 .. Manifest (Family_Relation_Unit).Path_Len);
         Discharge_Full : constant String := Authority_Dir & "/" &
           Manifest (Family_Relation_Discharge).Rel_Path (1 .. Manifest (Family_Relation_Discharge).Path_Len);

         Event_Res     : constant HRA_N.Storage.Event_Reader.Read_Result :=
           Read_Event_Memory_File (Event_Full);
         Val_Res       : constant Read_Validity_Result := Read_Validity_File (Val_Full);
         Desc_Res      : constant Read_Description_Result := Read_Description_File (Desc_Full);
         Locus_Res     : constant Read_Locus_Result := Read_Locus_File (Locus_Full);
         Unit_Res      : constant Unit_Read_Result := Read_Relation_Unit_File (Unit_Full);
         Discharge_Res : constant Discharge_Read_Result := Read_Relation_Discharge_File (Discharge_Full);

         Corrections   : Correction_Memory := (Count => 0, Values => [others => Empty_Correction]);
         Rev_Res       : HRA_N.Storage.Actual_Reversal_Reader.Read_Result;
      begin
         if not Event_Res.Success or else not Val_Res.Success or else not Desc_Res.Success
           or else not Locus_Res.Success or else not Unit_Res.Success or else not Discharge_Res.Success
         then
            Rollback (Tx);
            return Set_Error (Receipt, "loam: failed reading manifest authority family files");
         end if;

         --  Reversal authority must be present and valid
         if not Ada.Directories.Exists (Reversals_Path) then
            Rollback (Tx);
            return Set_Error
              (Receipt,
               "loam: Actual reversal authority is missing; Correction cannot prove reversal independence");
         end if;

         Rev_Res := Read_Actual_Reversal_File (Reversals_Path);
         if not Rev_Res.Success then
            Rollback (Tx);
            return Set_Error
              (Receipt, "loam: Actual reversal authority is malformed or unsupported");
         end if;

         --  Correction sidecar
         if Ada.Directories.Exists (Correction_Path) then
            declare
               Corr_Read : constant HRA_N.Storage.Correction.Read_Result :=
                 HRA_N.Storage.Correction.Read_File (Correction_Path);
            begin
               if not Corr_Read.Success then
                  Rollback (Tx);
                  return Set_Error
                    (Receipt, "loam: malformed or unsupported correction-memory file");
               end if;
               Corrections := Corr_Read.Memory;
            end;
         end if;

         --  3. Domain Admission checks
         if not Loci_Admitted (Locus_Res.Vocabulary, Draft.Effects) then
            Rollback (Tx);
            return Set_Error
              (Receipt, "loam: correction replacement uses a Locus not approved for new publication");
         end if;

         declare
            Target_Ev    : Event;
            Target_Found : constant Boolean :=
              Find_Target_Event (Event_Res.Events, Draft.Target, Target_Ev);
         begin
            if not Target_Found then
               Rollback (Tx);
               return Set_Error (Receipt, "loam: selected correction target is not retained");
            end if;

            if not Movement_Effects_Valid (Effects (Target_Ev)) then
               Rollback (Tx);
               return Set_Error
                 (Receipt,
                  "loam: selected Actual is outside the practical balanced-JPY correction entrance");
            end if;
         end;

         if Relations_Mention_Event (Unit_Res.Memory, Discharge_Res.Memory, Draft.Target) then
            Rollback (Tx);
            return Set_Error
              (Receipt,
               "loam: correction of an Event already referenced by relation/discharge evidence is not yet qualified");
         end if;

         if Reversals_Mention_Event (Rev_Res.Memory, Draft.Target) then
            Rollback (Tx);
            return Set_Error
              (Receipt,
               "loam: correction of an Actual participating in Reversal evidence is not yet qualified");
         end if;

         --  4. Pending correction inspection
         declare
            Pending_Count : Natural := 0;
            Pending_Idx   : Positive := 1;
         begin
            for I in 1 .. Corrections.Count loop
               if Equal_Token (Corrections.Values (I).Target.Token, Draft.Target.Token) then
                  Pending_Count := Pending_Count + 1;
                  Pending_Idx := I;
               end if;
            end loop;

            if Pending_Count > 1 then
               Rollback (Tx);
               return Set_Error
                 (Receipt,
                  "loam: multiple correction relations target the selected Actual; no retry winner is implied");
            end if;

            declare
               Correction_Changed : Boolean := False;
               Selected_Corr      : Event_Correction;
               Replacement_Id     : Event_Id;
               Corr_Id            : Correction_Id;
            begin
               if Pending_Count = 1 then
                  --  Retry / resume existing pending correction
                  declare
                     Pending : constant Event_Correction := Corrections.Values (Pending_Idx);
                  begin
                     if Events_Mention_Event (Event_Res.Events, Pending.Replacement) then
                        Rollback (Tx);
                        return Set_Error
                          (Receipt, "loam: selected Actual already has a published replacement");
                     end if;
                     Selected_Corr      := Pending;
                     Replacement_Id     := Pending.Replacement;
                     Corr_Id            := Pending.Id;
                     Correction_Changed := False;
                  end;
               else
                  --  Target must be current tip
                  declare
                     Res : Resolution_Result;
                  begin
                     Resolve (Event_Res.Events, Corrections, Draft.Target, Res);
                     if Res.State /= Resolution_Current
                       or else not Equal_Token (Res.Effective.Token, Draft.Target.Token)
                     then
                        Rollback (Tx);
                        return Set_Error (Receipt, "loam: selected Actual is no longer current");
                     end if;
                  end;

                  Replacement_Id := Fresh_Replacement_Id
                    (Events      => Event_Res.Events,
                     Val         => Val_Res.Memory,
                     Desc        => Desc_Res.Memory,
                     Units       => Unit_Res.Memory,
                     Discharges  => Discharge_Res.Memory,
                     Corrections => Corrections,
                     Reversals   => Rev_Res.Memory);

                  if Replacement_Id.Token.Length = 0 then
                     Rollback (Tx);
                     return Set_Error
                       (Receipt, "loam: could not generate a fresh replacement Event identity");
                  end if;

                  Corr_Id := Fresh_Correction_Id (Corrections);
                  if Corr_Id.Token.Length = 0 then
                     Rollback (Tx);
                     return Set_Error
                       (Receipt, "loam: could not generate a fresh correction identity");
                  end if;

                  Selected_Corr :=
                    (Id          => Corr_Id,
                     Target      => Draft.Target,
                     Replacement => Replacement_Id);
                  Correction_Changed := True;
               end if;

               if Descriptions_Mention_Event (Desc_Res.Memory, Replacement_Id)
                 or else Relations_Mention_Event (Unit_Res.Memory, Discharge_Res.Memory, Replacement_Id)
                 or else Reversals_Mention_Event (Rev_Res.Memory, Replacement_Id)
               then
                  Rollback (Tx);
                  return Set_Error
                    (Receipt, "loam: replacement identity collides with retained non-Event evidence");
               end if;

               --  5. Candidate world construction and frontier admission
               declare
                  Cand_Events      : Event_Vectors.Vector := Event_Res.Events;
                  Cand_Corrections : Correction_Memory    := Corrections;
                  New_Event        : constant Event :=
                    Make_Event (Replacement_Id, Draft.Effects);
               begin
                  Cand_Events.Append (New_Event);
                  if Correction_Changed then
                     if Cand_Corrections.Count >= Max_Corrections then
                        Rollback (Tx);
                        return Set_Error (Receipt, "loam: correction memory capacity exceeded");
                     end if;
                     Cand_Corrections.Count := Cand_Corrections.Count + 1;
                     Cand_Corrections.Values (Cand_Corrections.Count) := Selected_Corr;
                  end if;

                  if not Frontier_Admissible (Cand_Events, Cand_Corrections) then
                     Rollback (Tx);
                     return Set_Error
                       (Receipt, "loam: proposed correction does not justify one current record frontier");
                  end if;

                  declare
                     Front_Res : Resolution_Result;
                  begin
                     Resolve (Cand_Events, Cand_Corrections, Draft.Target, Front_Res);
                     if Front_Res.State /= Resolution_Current
                       or else not Equal_Token (Front_Res.Effective.Token, Replacement_Id.Token)
                     then
                        Rollback (Tx);
                        return Set_Error
                          (Receipt, "loam: proposed correction frontier did not select exactly the replacement");
                     end if;
                  end;

                  --  6. Date inheritance & description
                  declare
                     Target_Date  : Date_Type;
                     Date_Found   : Boolean;
                     Carried_Date : Boolean := False;
                     Has_Desc     : constant Boolean := Length (Draft.Description) > 0;

                     Old_Event_Text : constant String :=
                       To_String (Read_All (Event_Full));
                     Old_Val_Text   : constant String :=
                       To_String (Read_All (Val_Full));
                     Old_Desc_Text  : constant String :=
                       To_String (Read_All (Desc_Full));

                     New_Event_Text : constant String :=
                       Old_Event_Text & Format_Event_Append (Replacement_Id, Draft.Effects);
                     New_Val_Text   : Unbounded_String := To_Unbounded_String (Old_Val_Text);
                     New_Desc_Text  : Unbounded_String := To_Unbounded_String (Old_Desc_Text);

                     Updates : Update_Set :=
                       [others => (Changed => False, Content => Null_Unbounded_String)];
                  begin
                     Find_Occurrence_Date (Val_Res.Memory, Draft.Target, Target_Date, Date_Found);
                     if Date_Found then
                        Carried_Date := True;
                        Append
                          (New_Val_Text,
                           "BASE" & ASCII.HT &
                           Replacement_Id.Token.Value (1 .. Replacement_Id.Token.Length) &
                           ASCII.HT & Format_Iso_Date (Target_Date) & ASCII.LF);
                     end if;

                     if Has_Desc then
                        Append
                          (New_Desc_Text,
                           "DESC" & ASCII.HT &
                           Replacement_Id.Token.Value (1 .. Replacement_Id.Token.Length) &
                           ASCII.HT & Escape_Text (To_String (Draft.Description)) & ASCII.LF);
                     end if;

                     --  7. Step 9: Persist Correction sidecar first
                     if Correction_Changed then
                        declare
                           Encoded : constant String :=
                             HRA_N.Storage.Correction.Encode (Cand_Corrections);
                        begin
                           if not Write_File_Atomically (Correction_Path, Encoded, Err, Err_Len) then
                              Rollback (Tx);
                              return Set_Error
                                (Receipt, "loam: correction relation could not be published");
                           end if;
                        end;
                     end if;

                     --  Fault hook: simulate crash after sidecar write before CURRENT
                     if Fault = Correction_Fault_Interrupt_After_Sidecar then
                        Rollback (Tx);
                        Receipt.Success      := False;
                        Receipt.Target       := Draft.Target;
                        Receipt.Replacement  := Replacement_Id;
                        Receipt.Correction   := Corr_Id;
                        Receipt.Error_Len    := 42;
                        Receipt.Error_Reason (1 .. 42) :=
                          "Interrupted after correction sidecar write";
                        return Receipt;
                     end if;

                     --  8. Step 10: Commit replacement Event to CURRENT last
                     Updates (Family_Event) :=
                       (Changed => True, Content => To_Unbounded_String (New_Event_Text));
                     Updates (Family_Actual_Validity) :=
                       (Changed => Carried_Date, Content => New_Val_Text);
                     if Has_Desc then
                        Updates (Family_Event_Description) :=
                          (Changed => True, Content => New_Desc_Text);
                     end if;

                     if not Commit (Tx, Updates, Err, Err_Len) then
                        Rollback (Tx);
                        return Set_Error (Receipt, Err (1 .. Err_Len));
                     end if;

                     Receipt.Success               := True;
                     Receipt.Target                := Draft.Target;
                     Receipt.Replacement           := Replacement_Id;
                     Receipt.Correction            := Corr_Id;
                     Receipt.Carried_Date          := Carried_Date;
                     Receipt.Published_Description := Has_Desc;
                     Receipt.Resumed               := not Correction_Changed;
                     return Receipt;
                  end;
               end;
            end;
         end;
      end;
   end Publish_Correction;

end HRA_N.Application.Correction_Publisher;
