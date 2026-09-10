-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Actual_Validity_Publisher
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with HRA_N.Core.Event;       use HRA_N.Core.Event;
with HRA_N.Core.Correction;  use HRA_N.Core.Correction;
with HRA_N.Application.Authority_Transaction; use HRA_N.Application.Authority_Transaction;
with HRA_N.Application.Correction_Frontier;   use HRA_N.Application.Correction_Frontier;
with HRA_N.Application.Actual_Validity_Frontier; use HRA_N.Application.Actual_Validity_Frontier;
with HRA_N.Storage.Manifest;         use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;     use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Validity_Reader;  use HRA_N.Storage.Validity_Reader;
with HRA_N.Storage.Correction;       use HRA_N.Storage.Correction;

package body HRA_N.Application.Actual_Validity_Publisher is

   function Set_Error (Receipt : in out Date_Receipt; Msg : String) return Date_Receipt is
   begin
      Receipt.Success   := False;
      Receipt.Error_Len := Natural'Min (Msg'Length, Receipt.Error_Reason'Length);
      Receipt.Error_Reason (1 .. Receipt.Error_Len) :=
        Msg (Msg'First .. Msg'First + Receipt.Error_Len - 1);
      return Receipt;
   end Set_Error;

   function Load_Corrections_Or_Empty
     (Path       : String;
      Memory     : out Correction_Memory;
      Reason     : out String;
      Reason_Len : out Natural) return Boolean
   is
   begin
      Reason_Len := 0;
      if not Ada.Directories.Exists (Path) then
         Memory := (Count => 0, Values => [others => Empty_Correction]);
         return True;
      end if;

      declare
         Res : constant HRA_N.Storage.Correction.Read_Result :=
           HRA_N.Storage.Correction.Read_File (Path);
      begin
         if Res.Success then
            Memory := Res.Memory;
            return True;
         else
            Reason_Len := Natural'Min (Res.Error_Len, Reason'Length);
            Reason (Reason'First .. Reason'First + Reason_Len - 1) :=
              Res.Error_Reason (Res.Error_Reason'First .. Res.Error_Reason'First + Reason_Len - 1);
            return False;
         end if;
      end;
   end Load_Corrections_Or_Empty;

   function Publish_Date
     (Authority_Dir   : String;
      Correction_Path : String;
      Target          : Event_Id;
      Valid_On        : Date_Type) return Date_Receipt
   is
      Receipt : Date_Receipt;
      Tx      : Transaction;
      Err     : String (1 .. 256) := [others => ' '];
      Err_Len : Natural           := 0;
   begin
      if Authority_Dir'Length = 0 then
         return Set_Error (Receipt, "loam: LOAM_MOVEMENT_MANIFEST_ROOT must not be empty");
      end if;
      if Correction_Path'Length = 0 then
         return Set_Error (Receipt, "loam: correction path must not be empty");
      end if;

      --  1. Open writer lock and transaction
      if not Open_Transaction (Authority_Dir, Tx, Err, Err_Len) then
         return Set_Error (Receipt, Err (1 .. Err_Len));
      end if;

      --  2. Re-read manifest authority under lock
      declare
         Man_Res : constant Read_Manifest_Result :=
           Read_Manifest_File (Authority_Dir & "/CURRENT");
         Failed_Fam : Manifest_Family;
      begin
         if not Man_Res.Success then
            Rollback (Tx);
            return Set_Error (Receipt, Man_Res.Error_Reason (1 .. Man_Res.Error_Len));
         end if;

         if not Verify_All_Objects (Authority_Dir, Man_Res.Manifest, Failed_Fam) then
            Rollback (Tx);
            return Set_Error (Receipt, "loam: authority object digest verification failed");
         end if;

         --  3. Re-read Events and Corrections under lock
         declare
            Event_Rel : constant String :=
              Man_Res.Manifest (Family_Event).Rel_Path
                (1 .. Man_Res.Manifest (Family_Event).Path_Len);
            Event_Full : constant String := Authority_Dir & "/" & Event_Rel;
            Event_Res  : constant HRA_N.Storage.Event_Reader.Read_Result :=
              Read_Event_Memory_File (Event_Full);

            Corrections : Correction_Memory;
            Corr_Err    : String (1 .. 256) := [others => ' '];
            Corr_Err_L  : Natural           := 0;
         begin
            if not Event_Res.Success then
               Rollback (Tx);
               return Set_Error (Receipt, Event_Res.Error_Reason (1 .. Event_Res.Error_Len));
            end if;

            if not Load_Corrections_Or_Empty (Correction_Path, Corrections, Corr_Err, Corr_Err_L) then
               Rollback (Tx);
               return Set_Error (Receipt, Corr_Err (1 .. Corr_Err_L));
            end if;

            --  4. Verify target is retained in Event memory
            declare
               Target_Retained : Boolean := False;
            begin
               for Ev of Event_Res.Events loop
                  if Equal_Token (Id (Ev).Token, Target.Token) then
                     Target_Retained := True;
                     exit;
                  end if;
               end loop;

               if not Target_Retained then
                  Rollback (Tx);
                  return Set_Error (Receipt, "loam: selected date-correction target is not retained");
               end if;
            end;

            --  5. Verify target is current tip in Correction frontier
            if not Frontier_Admissible (Event_Res.Events, Corrections) then
               Rollback (Tx);
               return Set_Error (Receipt, "loam: movement corrections do not justify one current record frontier");
            end if;

            declare
               Front_Res : Resolution_Result;
            begin
               Resolve (Event_Res.Events, Corrections, Target, Front_Res);
               if Front_Res.State /= Resolution_Current
                 or else not Equal_Token (Front_Res.Effective.Token, Target.Token)
               then
                  Rollback (Tx);
                  return Set_Error (Receipt, "loam: selected Actual is no longer current");
               end if;
            end;

            --  6. Re-read ActualValidity under lock
            declare
               Val_Rel : constant String :=
                 Man_Res.Manifest (Family_Actual_Validity).Rel_Path
                   (1 .. Man_Res.Manifest (Family_Actual_Validity).Path_Len);
               Val_Full : constant String := Authority_Dir & "/" & Val_Rel;
               Val_Res  : constant Read_Validity_Result := Read_Validity_File (Val_Full);
            begin
               if not Val_Res.Success then
                  Rollback (Tx);
                  return Set_Error (Receipt, Val_Res.Error_Reason (1 .. Val_Res.Error_Len));
               end if;

               declare
                  Curr_Fact  : Validity_Fact;
                  Curr_Found : Boolean;
               begin
                  Find_Current_Fact (Val_Res.History, Target, Curr_Fact, Curr_Found);

                  if Curr_Found then
                     --  Case A: Target already has a current occurrence date
                     if Equal_Date (Curr_Fact.Valid_On, Valid_On) then
                        --  Exact same date: no-op, manifest authority unchanged
                        Rollback (Tx);
                        Receipt.Success      := True;
                        Receipt.Target       := Target;
                        Receipt.Has_Previous := True;
                        Receipt.Previous     := Curr_Fact.Valid_On;
                        Receipt.Valid_On     := Valid_On;
                        Receipt.Changed      := False;
                        Receipt.First_Date   := False;
                        return Receipt;
                     end if;

                     --  Different date: append revision fact + correction
                     declare
                        Cand_History : Validity_History := Val_Res.History;
                        Fact_Id      : constant Validity_Fact_Id := Fresh_Fact_Id (Cand_History);
                        Corr_Id      : constant Validity_Correction_Id := Fresh_Correction_Id (Cand_History);
                     begin
                        if Fact_Id.Token.Length = 0 or else Corr_Id.Token.Length = 0 then
                           Rollback (Tx);
                           return Set_Error (Receipt, "loam: could not generate fresh occurrence-date identity");
                        end if;

                        if Cand_History.Fact_Count = Max_Validity_Facts
                          or else Cand_History.Correction_Count = Max_Validity_Corrections
                        then
                           Rollback (Tx);
                           return Set_Error (Receipt, "loam: actual-validity memory capacity exceeded");
                        end if;

                        Cand_History.Fact_Count := Cand_History.Fact_Count + 1;
                        Cand_History.Facts (Cand_History.Fact_Count) :=
                          (Id       => Fact_Id,
                           Event_Id => Target,
                           Valid_On => Valid_On);

                        Cand_History.Correction_Count := Cand_History.Correction_Count + 1;
                        Cand_History.Corrections (Cand_History.Correction_Count) :=
                          (Id          => Corr_Id,
                           Target      => Curr_Fact.Id,
                           Replacement => Fact_Id);

                        if not Frontier_Admissible (Cand_History) then
                           Rollback (Tx);
                           return Set_Error
                             (Receipt, "loam: proposed date correction does not justify one current date per Event");
                        end if;

                        declare
                           Check_Fact  : Validity_Fact;
                           Check_Found : Boolean;
                        begin
                           Find_Current_Fact (Cand_History, Target, Check_Fact, Check_Found);
                           if not Check_Found or else not Equal_Date (Check_Fact.Valid_On, Valid_On) then
                              Rollback (Tx);
                              return Set_Error
                                (Receipt, "loam: proposed date correction frontier did not select the replacement date");
                           end if;
                        end;

                        --  Serialize and commit under Authority_Transaction
                        declare
                           New_Val_Text : constant String := Format_Validity_History (Cand_History);
                           Updates      : Update_Set :=
                             [others => (Changed => False, Content => Null_Unbounded_String)];
                        begin
                           Updates (Family_Actual_Validity) :=
                             (Changed => True, Content => To_Unbounded_String (New_Val_Text));

                           if not Commit (Tx, Updates, Err, Err_Len) then
                              Rollback (Tx);
                              return Set_Error (Receipt, Err (1 .. Err_Len));
                           end if;

                           Receipt.Success      := True;
                           Receipt.Target       := Target;
                           Receipt.Has_Previous := True;
                           Receipt.Previous     := Curr_Fact.Valid_On;
                           Receipt.Valid_On     := Valid_On;
                           Receipt.Changed      := True;
                           Receipt.First_Date   := False;
                           return Receipt;
                        end;
                     end;
                  else
                     --  Case B: Target is undated (first date attachment)
                     declare
                        Cand_History : Validity_History := Val_Res.History;
                        Fact_Id      : constant Validity_Fact_Id := Fresh_Fact_Id (Cand_History);
                     begin
                        if Fact_Id.Token.Length = 0 then
                           Rollback (Tx);
                           return Set_Error (Receipt, "loam: could not generate fresh occurrence-date identity");
                        end if;

                        if Cand_History.Fact_Count = Max_Validity_Facts then
                           Rollback (Tx);
                           return Set_Error (Receipt, "loam: actual-validity memory capacity exceeded");
                        end if;

                        Cand_History.Fact_Count := Cand_History.Fact_Count + 1;
                        Cand_History.Facts (Cand_History.Fact_Count) :=
                          (Id       => Fact_Id,
                           Event_Id => Target,
                           Valid_On => Valid_On);

                        if not Frontier_Admissible (Cand_History) then
                           Rollback (Tx);
                           return Set_Error
                             (Receipt, "loam: proposed first date does not justify one current date per Event");
                        end if;

                        declare
                           Check_Fact  : Validity_Fact;
                           Check_Found : Boolean;
                        begin
                           Find_Current_Fact (Cand_History, Target, Check_Fact, Check_Found);
                           if not Check_Found or else not Equal_Date (Check_Fact.Valid_On, Valid_On) then
                              Rollback (Tx);
                              return Set_Error
                                (Receipt, "loam: proposed first date frontier did not select the supplied date");
                           end if;
                        end;

                        --  Serialize and commit under Authority_Transaction
                        declare
                           New_Val_Text : constant String := Format_Validity_History (Cand_History);
                           Updates      : Update_Set :=
                             [others => (Changed => False, Content => Null_Unbounded_String)];
                        begin
                           Updates (Family_Actual_Validity) :=
                             (Changed => True, Content => To_Unbounded_String (New_Val_Text));

                           if not Commit (Tx, Updates, Err, Err_Len) then
                              Rollback (Tx);
                              return Set_Error (Receipt, Err (1 .. Err_Len));
                           end if;

                           Receipt.Success      := True;
                           Receipt.Target       := Target;
                           Receipt.Has_Previous := False;
                           Receipt.Previous     := Valid_On;
                           Receipt.Valid_On     := Valid_On;
                           Receipt.Changed      := True;
                           Receipt.First_Date   := True;
                           return Receipt;
                        end;
                     end;
                  end if;
               end;
            end;
         end;
      end;
   end Publish_Date;

   function Publish_Date
     (Authority_Dir   : String;
      Correction_Path : String;
      Target_Str      : String;
      Date_Str        : String) return Date_Receipt
   is
      Receipt  : Date_Receipt;
      Parsed_D : Date_Type;
   begin
      if Target_Str'Length = 0 or else Target_Str'Length > Max_Token_Length then
         return Set_Error (Receipt, "loam: invalid target event id");
      end if;
      if not Parse_Iso_Date (Date_Str, Parsed_D) then
         return Set_Error (Receipt, "loam: date must be a real calendar date in YYYY-MM-DD form");
      end if;
      return Publish_Date
        (Authority_Dir   => Authority_Dir,
         Correction_Path => Correction_Path,
         Target          => (Token => Make_Token (Target_Str)),
         Valid_On        => Parsed_D);
   end Publish_Date;

end HRA_N.Application.Actual_Validity_Publisher;
