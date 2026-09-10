-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Scheduled_Replacement_Publisher
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;              use Ada.Strings.Fixed;
with HRA_N.Storage.Sync;             use HRA_N.Storage.Sync;
with HRA_N.Storage.Manifest;         use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;     use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Scheduled_Reader; use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Scheduled_Writer; use HRA_N.Storage.Scheduled_Writer;
with HRA_N.Core.Admission;          use HRA_N.Core.Admission;
with HRA_N.Storage.Locus_Reader;     use HRA_N.Storage.Locus_Reader;
with HRA_N.Application.Scheduled_Inspection; use HRA_N.Application.Scheduled_Inspection;

package body HRA_N.Application.Scheduled_Replacement_Publisher is

   function Set_Error
     (Receipt : in out Replacement_Receipt;
      Msg     : String) return Replacement_Receipt
   is
      Len : constant Natural := Natural'Min (Msg'Length, Receipt.Error_Reason'Length);
   begin
      Receipt.Success      := False;
      Receipt.Error_Len    := Len;
      Receipt.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Receipt;
   end Set_Error;

   function Make_Two_Party_Draft
     (Source      : String;
      From_Locus  : String;
      To_Locus    : String;
      Amount      : Quanta_Type;
      Valid_On    : Date_Type;
      Measure_Str : String := "jpy") return Replacement_Draft
   is
      Draft : Replacement_Draft;
   begin
      Draft.Source       := (Token => Make_Token (Source));
      Draft.Scheduled_On := Valid_On;
      Draft.From_Len     := Natural'Min (From_Locus'Length, Draft.From_Locus'Length);
      Draft.From_Locus (1 .. Draft.From_Len) :=
        From_Locus (From_Locus'First .. From_Locus'First + Draft.From_Len - 1);
      Draft.To_Len       := Natural'Min (To_Locus'Length, Draft.To_Locus'Length);
      Draft.To_Locus (1 .. Draft.To_Len) :=
        To_Locus (To_Locus'First .. To_Locus'First + Draft.To_Len - 1);
      Draft.Amount       := Amount;
      Draft.Measure      := (Token => Make_Token (Measure_Str));
      return Draft;
   end Make_Two_Party_Draft;

   function Fresh_Scheduled_Id
     (Lifecycle : Scheduled_Lifecycle) return Scheduled_Id
   is
      function Id_Exists (Tok : String) return Boolean is
      begin
         for I in 1 .. Lifecycle.Sched_Count loop
            declare
               Item_Tok : constant String :=
                 Lifecycle.Sched_Items (I).Id.Token.Value
                   (1 .. Lifecycle.Sched_Items (I).Id.Token.Length);
            begin
               if Item_Tok = Tok then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Id_Exists;

   begin
      for N in 1 .. Lifecycle.Sched_Count + 100 loop
         declare
            N_Str     : constant String := Trim (Natural'Image (N), Ada.Strings.Both);
            Candidate : constant String := "scheduled-" & N_Str;
         begin
            if not Id_Exists (Candidate) then
               return (Token => Make_Token (Candidate));
            end if;
         end;
      end loop;
      return (Token => (Length => 0, Value => [others => ' ']));
   end Fresh_Scheduled_Id;

   function Publish_Replacement
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Draft          : Replacement_Draft) return Replacement_Receipt
   is
      Receipt         : Replacement_Receipt;
      Sched_Lock_Path : constant String := Scheduled_Path & ".loam-writer-lock";
      Sched_Lock      : Lock_Handle;
      Auth_Lock_Path  : constant String := Authority_Dir & "/CURRENT.loam-writer-lock";
      Auth_Lock       : Lock_Handle;
   begin
      if Scheduled_Path'Length = 0 then
         return Set_Error (Receipt, "loam: scheduled path must not be empty");
      end if;
      if Authority_Dir'Length = 0 then
         return Set_Error (Receipt, "loam: LOAM_MOVEMENT_MANIFEST_ROOT must not be empty");
      end if;

      if Draft.Amount <= 0 then
         return Set_Error (Receipt, "loam: Scheduled replacement requires a positive total matching the draft");
      end if;
      if Draft.From_Len = 0 or else Draft.To_Len = 0 then
         return Set_Error (Receipt, "loam: Scheduled replacement requires valid Locus tokens and nonzero JPY quantities");
      end if;
      if not Is_Valid_Date (Draft.Scheduled_On.Year, Draft.Scheduled_On.Month, Draft.Scheduled_On.Day) then
         return Set_Error (Receipt, "loam: replacement date must be a real calendar date in YYYY-MM-DD form");
      end if;

      --  1. Fixed ownership order: Scheduled lifecycle lock -> Movement CURRENT lock
      if not Acquire_Exclusive_Lock (Sched_Lock_Path, Sched_Lock) then
         return Set_Error (Receipt, "loam: failed to acquire scheduled lifecycle lock");
      end if;

      if not Acquire_Exclusive_Lock (Auth_Lock_Path, Auth_Lock) then
         Release_Lock (Sched_Lock);
         return Set_Error (Receipt, "loam: failed to acquire manifest writer lock");
      end if;

      --  2. Load Lifecycle and Movement Event frontier under locks
      declare
         Sched_Res : constant Read_Scheduled_Result := Read_Scheduled_File (Scheduled_Path);
         Man_Res   : constant Read_Manifest_Result  := Read_Manifest_File (Authority_Dir & "/CURRENT");
         Failed_Fam : Manifest_Family;
      begin
         if not Sched_Res.Success then
            Release_Lock (Auth_Lock);
            Release_Lock (Sched_Lock);
            return Set_Error (Receipt, "loam: " & Sched_Res.Error_Reason (1 .. Sched_Res.Error_Len));
         end if;

         if not Man_Res.Success then
            Release_Lock (Auth_Lock);
            Release_Lock (Sched_Lock);
            return Set_Error (Receipt, "loam: " & Man_Res.Error_Reason (1 .. Man_Res.Error_Len));
         end if;

         if not Verify_All_Objects (Authority_Dir, Man_Res.Manifest, Failed_Fam) then
            Release_Lock (Auth_Lock);
            Release_Lock (Sched_Lock);
            return Set_Error (Receipt, "loam: authority object digest verification failed");
         end if;

         declare
            Ev_Rel    : constant String :=
              Man_Res.Manifest (Family_Event).Rel_Path
                (1 .. Man_Res.Manifest (Family_Event).Path_Len);
            Ev_Res    : constant HRA_N.Storage.Event_Reader.Read_Result :=
              Read_Event_Memory_File (Authority_Dir & "/" & Ev_Rel);
            Loc_Rel   : constant String :=
              Man_Res.Manifest (Family_Locus_Admission).Rel_Path
                (1 .. Man_Res.Manifest (Family_Locus_Admission).Path_Len);
            Loc_Res   : constant Read_Locus_Result :=
              Read_Locus_File (Authority_Dir & "/" & Loc_Rel);
            Lifecycle : Scheduled_Lifecycle := Sched_Res.Lifecycle;
         begin
            if not Ev_Res.Success then
               Release_Lock (Auth_Lock);
               Release_Lock (Sched_Lock);
               return Set_Error (Receipt, "loam: " & Ev_Res.Error_Reason (1 .. Ev_Res.Error_Len));
            end if;

            if not Loc_Res.Success then
               Release_Lock (Auth_Lock);
               Release_Lock (Sched_Lock);
               return Set_Error (Receipt, "loam: " & Loc_Res.Error_Reason (1 .. Loc_Res.Error_Len));
            end if;

            declare
               From_Tok : constant Locus_Id := (Token => Make_Token (Draft.From_Locus (1 .. Draft.From_Len)));
               To_Tok   : constant Locus_Id := (Token => Make_Token (Draft.To_Locus (1 .. Draft.To_Len)));
            begin
               if not Admits_Locus (Loc_Res.Vocabulary, From_Tok) then
                  Release_Lock (Auth_Lock);
                  Release_Lock (Sched_Lock);
                  return Set_Error (Receipt, "loam: FROM locus is not admitted: " & Draft.From_Locus (1 .. Draft.From_Len));
               end if;

               if not Admits_Locus (Loc_Res.Vocabulary, To_Tok) then
                  Release_Lock (Auth_Lock);
                  Release_Lock (Sched_Lock);
                  return Set_Error (Receipt, "loam: TO locus is not admitted: " & Draft.To_Locus (1 .. Draft.To_Len));
               end if;
            end;

            --  3. Verify source is retained and currently open
            if not Sched_Exists (Lifecycle, Draft.Source) then
               Release_Lock (Auth_Lock);
               Release_Lock (Sched_Lock);
               return Set_Error (Receipt, "loam: selected Scheduled identity is not retained");
            end if;

            if Is_Replaced (Lifecycle, Draft.Source) then
               Release_Lock (Auth_Lock);
               Release_Lock (Sched_Lock);
               return Set_Error (Receipt, "loam: selected Scheduled identity is already replaced");
            end if;

            declare
               Open_Res : constant Open_Occurrences_Result :=
                 Current_Open_Scheduled (Lifecycle, Ev_Res.Events);
               Source_Open : Boolean := False;
            begin
               if Open_Res.Status /= Status_Ok then
                  Release_Lock (Auth_Lock);
                  Release_Lock (Sched_Lock);
                  return Set_Error (Receipt, "loam: Scheduled lifecycle authority is inconsistent");
               end if;

               for I in 1 .. Open_Res.Count loop
                  if Equal_Token (Open_Res.Occurrences (I).Id.Token, Draft.Source.Token) then
                     Source_Open := True;
                     exit;
                  end if;
               end loop;

               if not Source_Open then
                  Release_Lock (Auth_Lock);
                  Release_Lock (Sched_Lock);
                  return Set_Error (Receipt, "loam: only a currently open Scheduled identity can be replaced");
               end if;
            end;

            --  4. Construct fresh replacement Scheduled occurrence
            declare
               Fresh_Id : constant Scheduled_Id := Fresh_Scheduled_Id (Lifecycle);
            begin
               if Fresh_Id.Token.Length = 0 then
                  Release_Lock (Auth_Lock);
                  Release_Lock (Sched_Lock);
                  return Set_Error (Receipt, "loam: could not generate a fresh replacement Scheduled identity");
               end if;

               if Lifecycle.Sched_Count = Max_Scheduled_Entries
                 or else Lifecycle.Repl_Count = Max_Scheduled_Entries
               then
                  Release_Lock (Auth_Lock);
                  Release_Lock (Sched_Lock);
                  return Set_Error (Receipt, "loam: scheduled lifecycle capacity exceeded");
               end if;

               Lifecycle.Sched_Count := Lifecycle.Sched_Count + 1;
               Lifecycle.Sched_Items (Lifecycle.Sched_Count) :=
                 (Id           => Fresh_Id,
                  Expected_Day => Draft.Scheduled_On,
                  Measure      => Draft.Measure,
                  Changes      =>
                    (Count  => 2,
                     Values =>
                       [1 => (Locus  => (Token => Make_Token (Draft.From_Locus (1 .. Draft.From_Len))),
                              Amount => -Draft.Amount),
                        2 => (Locus  => (Token => Make_Token (Draft.To_Locus (1 .. Draft.To_Len))),
                              Amount => Draft.Amount),
                        others => (Locus => (Token => (Length => 0, Value => [others => ' '])), Amount => 0)]));

               Lifecycle.Repl_Count := Lifecycle.Repl_Count + 1;
               Lifecycle.Repl_Items (Lifecycle.Repl_Count) :=
                 (Original    => Draft.Source,
                  Replaced_By => Fresh_Id);

               --  5. Verify transition admissibility: source closed, replacement current-open
               declare
                  Post_Open : constant Open_Occurrences_Result :=
                    Current_Open_Scheduled (Lifecycle, Ev_Res.Events);
                  Source_Closed : Boolean := True;
                  Repl_Open     : Boolean := False;
               begin
                  if Post_Open.Status /= Status_Ok then
                     Release_Lock (Auth_Lock);
                     Release_Lock (Sched_Lock);
                     return Set_Error (Receipt, "loam: proposed Scheduled replacement graph is invalid");
                  end if;

                  for I in 1 .. Post_Open.Count loop
                     if Equal_Token (Post_Open.Occurrences (I).Id.Token, Draft.Source.Token) then
                        Source_Closed := False;
                     end if;
                     if Equal_Token (Post_Open.Occurrences (I).Id.Token, Fresh_Id.Token) then
                        Repl_Open := True;
                     end if;
                  end loop;

                  if not Source_Closed then
                     Release_Lock (Auth_Lock);
                     Release_Lock (Sched_Lock);
                     return Set_Error (Receipt, "loam: proposed Scheduled replacement did not close its source");
                  end if;

                  if not Repl_Open then
                     Release_Lock (Auth_Lock);
                     Release_Lock (Sched_Lock);
                     return Set_Error (Receipt, "loam: proposed Scheduled replacement did not expose its replacement as current-open");
                  end if;
               end;

               --  6. Atomically persist updated Scheduled lifecycle authority
               declare
                  Write_Res : constant Write_Scheduled_Result :=
                    Write_Scheduled_Lifecycle (Scheduled_Path, Lifecycle);
               begin
                  Release_Lock (Auth_Lock);
                  Release_Lock (Sched_Lock);

                  if not Write_Res.Success then
                     return Set_Error (Receipt, "loam: " & Write_Res.Error_Reason (1 .. Write_Res.Error_Len));
                  end if;

                  Receipt.Success      := True;
                  Receipt.Source       := Draft.Source;
                  Receipt.Replacement  := Fresh_Id;
                  Receipt.Scheduled_On := Draft.Scheduled_On;
                  Receipt.Amount       := Draft.Amount;
                  return Receipt;
               end;
            end;
         end;
      end;
   end Publish_Replacement;

end HRA_N.Application.Scheduled_Replacement_Publisher;
