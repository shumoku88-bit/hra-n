-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Scheduled_Publisher
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;              use Ada.Strings.Fixed;
with HRA_N.Core.Admission;          use HRA_N.Core.Admission;
with HRA_N.Storage.Sync;             use HRA_N.Storage.Sync;
with HRA_N.Storage.Manifest;         use HRA_N.Storage.Manifest;
with HRA_N.Storage.Locus_Reader;     use HRA_N.Storage.Locus_Reader;
with HRA_N.Storage.Scheduled_Reader; use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Scheduled_Writer; use HRA_N.Storage.Scheduled_Writer;
with HRA_N.Application.Publisher;    use HRA_N.Application.Publisher;

package body HRA_N.Application.Scheduled_Publisher is

   function Set_Error
     (Result : in out Scheduled_Publish_Result;
      Msg    : String) return Scheduled_Publish_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Set_Mutation_Error
     (Result : in out Scheduled_Mutation_Result;
      Msg    : String) return Scheduled_Mutation_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Mutation_Error;

   function Extract_Scheduled_Number (Id_Str : String) return Natural is
      Prefix : constant String := "scheduled-";
   begin
      if Id_Str'Length > Prefix'Length
        and then Id_Str (Id_Str'First .. Id_Str'First + Prefix'Length - 1) = Prefix
      then
         begin
            return Natural'Value (Id_Str (Id_Str'First + Prefix'Length .. Id_Str'Last));
         exception
            when others =>
               return 0;
         end;
      end if;
      return 0;
   end Extract_Scheduled_Number;

   function Complete_Scheduled_Movement
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Target_Id      : Scheduled_Id;
      Valid_On       : Date_Type;
      Description    : String := "") return Scheduled_Publish_Result
   is
      Result : Scheduled_Publish_Result;

      --  1. Preflight inspection of Scheduled lifecycle authority
      Read_Res : constant Read_Scheduled_Result :=
        Read_Scheduled_File (Scheduled_Path);

      Target_Str : constant String :=
        Target_Id.Token.Value (1 .. Target_Id.Token.Length);

      Sched_Lock_Path : constant String := Scheduled_Path & ".loam-writer-lock";
      Sched_Lock      : Lock_Handle;

      Ev_Id_Str : constant String := "scheduled-completion:" & Target_Str;
      Ev_Id     : constant Event_Id := (Token => Make_Token (Ev_Id_Str));
   begin
      if not Read_Res.Success then
         return Set_Error
           (Result, "Failed to read scheduled lifecycle: " &
                    Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
      end if;

      declare
         Lookup : constant Lookup_Result :=
           Find_Occurrence (Read_Res.Lifecycle, Target_Id);
      begin
         if not Lookup.Found then
            return Set_Error (Result, "Scheduled occurrence not found: " & Target_Str);
         end if;

         if not Is_Current_Open (Read_Res.Lifecycle, Target_Id) then
            return Set_Error (Result, "Scheduled occurrence is not current-open: " & Target_Str);
         end if;

         --  Extract balanced 2-party movement shape
         declare
            Occ : constant Scheduled_Occurrence := Lookup.Item;
            From_Locus : String (1 .. Max_Token_Length) := [others => ' '];
            From_Len   : Natural := 0;
            To_Locus   : String (1 .. Max_Token_Length) := [others => ' '];
            To_Len     : Natural := 0;
            Amount     : Quanta_Type := 0;
         begin
            if Occ.Changes.Count /= 2 then
               return Set_Error (Result, "Multi-party scheduled movements not supported in this slice");
            end if;

            for I in 1 .. 2 loop
               declare
                  Chg     : constant Scheduled_Change := Occ.Changes.Values (I);
                  Tok_Str : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
               begin
                  if Chg.Amount < 0 then
                     From_Len := Tok_Str'Length;
                     From_Locus (1 .. From_Len) := Tok_Str;
                     Amount := -Chg.Amount;
                  elsif Chg.Amount > 0 then
                     To_Len := Tok_Str'Length;
                     To_Locus (1 .. To_Len) := Tok_Str;
                  end if;
               end;
            end loop;

            if From_Len = 0 or else To_Len = 0 or else Amount <= 0 then
               return Set_Error (Result, "Scheduled changes do not define a balanced FROM/TO pair");
            end if;

            --  2. Acquire Scheduled lifecycle writer ownership
            if not Acquire_Exclusive_Lock (Sched_Lock_Path, Sched_Lock) then
               return Set_Error (Result, "Failed to acquire scheduled lifecycle lock");
            end if;

            --  3. Publish movement under manifest authority with exact scheduled-completion ID
            declare
               Pub_Res : constant Publish_Result :=
                 Publish_Movement
                   (Authority_Dir => Authority_Dir,
                    From_Locus    => From_Locus (1 .. From_Len),
                    To_Locus      => To_Locus (1 .. To_Len),
                    Amount        => Amount,
                    Valid_On      => Valid_On,
                    Description   => Description,
                    Explicit_Id   => Ev_Id_Str);
            begin
               if not Pub_Res.Success then
                  Release_Lock (Sched_Lock);
                  return Set_Error
                    (Result, "Movement publication failed: " &
                             Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
               end if;

               --  4. Append Completion to Scheduled lifecycle authority
               declare
                  Write_Res : constant Write_Scheduled_Result :=
                    Append_Completion
                      (Scheduled_Path => Scheduled_Path,
                       Target         => Target_Id,
                       Actual_Event   => Ev_Id);
               begin
                  Release_Lock (Sched_Lock);

                  if not Write_Res.Success then
                     return Set_Error
                       (Result, "Failed to register completion: " &
                                Write_Res.Error_Reason (1 .. Write_Res.Error_Len));
                  end if;

                  Result.Success := True;
                  Result.Event_Id_Len := Ev_Id_Str'Length;
                  Result.Event_Id_Str (1 .. Ev_Id_Str'Length) := Ev_Id_Str;
                  return Result;
               end;
            end;
         end;
      end;
   end Complete_Scheduled_Movement;

   function Add_Scheduled_Obligation
     (Scheduled_Path : String;
      Authority_Dir  : String;
      From_Locus     : String;
      To_Locus       : String;
      Amount         : Quanta_Type;
      Valid_On       : Date_Type;
      Measure_Str    : String := "jpy") return Scheduled_Mutation_Result
   is
      Result          : Scheduled_Mutation_Result;
      Sched_Lock_Path : constant String := Scheduled_Path & ".loam-writer-lock";
      Sched_Lock      : Lock_Handle;
   begin
      if Amount <= 0 then
         return Set_Mutation_Error (Result, "Scheduled amount must be greater than zero");
      end if;

      if From_Locus'Length = 0 or else To_Locus'Length = 0 then
         return Set_Mutation_Error (Result, "Locus names cannot be empty");
      end if;

      if From_Locus = To_Locus then
         return Set_Mutation_Error (Result, "FROM and TO loci must be distinct");
      end if;

      --  1. Verify loci against LocusAdmission vocabulary in CURRENT manifest
      declare
         Manifest_Res : constant Read_Manifest_Result :=
           Read_Manifest_File (Authority_Dir & "/CURRENT");
      begin
         if not Manifest_Res.Success then
            return Set_Mutation_Error
              (Result, "Failed to read manifest: " &
                       Manifest_Res.Error_Reason (1 .. Manifest_Res.Error_Len));
         end if;

         if not Manifest_Res.Manifest (Family_Locus_Admission).Present then
            return Set_Mutation_Error (Result, "LocusAdmission family missing in manifest");
         end if;

         declare
            Locus_Item : constant Manifest_Item :=
              Manifest_Res.Manifest (Family_Locus_Admission);
            Locus_Rel  : constant String :=
              Locus_Item.Rel_Path (1 .. Locus_Item.Path_Len);
            Locus_Res  : constant Read_Locus_Result :=
              Read_Locus_File (Authority_Dir & "/" & Locus_Rel);
         begin
            if not Locus_Res.Success then
               return Set_Mutation_Error (Result, "Failed to read admitted loci vocabulary");
            end if;

            declare
               From_Tok : constant Locus_Id := (Token => Make_Token (From_Locus));
               To_Tok   : constant Locus_Id := (Token => Make_Token (To_Locus));
            begin
               if not Admits_Locus (Locus_Res.Vocabulary, From_Tok) then
                  return Set_Mutation_Error (Result, "FROM locus is not admitted: " & From_Locus);
               end if;
               if not Admits_Locus (Locus_Res.Vocabulary, To_Tok) then
                  return Set_Mutation_Error (Result, "TO locus is not admitted: " & To_Locus);
               end if;
            end;
         end;
      end;

      --  2. Determine next sequential scheduled ID
      declare
         Read_Res : constant Read_Scheduled_Result :=
           Read_Scheduled_File (Scheduled_Path);
         Max_N    : Natural := 0;
      begin
         if not Read_Res.Success then
            return Set_Mutation_Error
              (Result, "Failed to read scheduled file: " &
                       Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
         end if;

         for I in 1 .. Read_Res.Lifecycle.Sched_Count loop
            declare
               Id_Str : constant String :=
                 Read_Res.Lifecycle.Sched_Items (I).Id.Token.Value
                   (1 .. Read_Res.Lifecycle.Sched_Items (I).Id.Token.Length);
               N      : constant Natural := Extract_Scheduled_Number (Id_Str);
            begin
               if N > Max_N then
                  Max_N := N;
               end if;
            end;
         end loop;

         declare
            Next_Id_Str : constant String :=
              "scheduled-" & Trim (Natural'Image (Max_N + 1), Ada.Strings.Both);
            Target_Id   : constant Scheduled_Id :=
              (Token => Make_Token (Next_Id_Str));
            Measure_Tok : constant Measure_Id :=
              (Token => Make_Token (Measure_Str));
         begin
            --  3. Acquire Scheduled lifecycle writer ownership
            if not Acquire_Exclusive_Lock (Sched_Lock_Path, Sched_Lock) then
               return Set_Mutation_Error (Result, "Failed to acquire scheduled lifecycle lock");
            end if;

            declare
               Write_Res : constant Write_Scheduled_Result :=
                 Append_Scheduled
                   (Scheduled_Path => Scheduled_Path,
                    Target         => Target_Id,
                    Valid_On       => Valid_On,
                    From_Locus     => From_Locus,
                    To_Locus       => To_Locus,
                    Amount         => Amount,
                    Measure        => Measure_Tok);
            begin
               Release_Lock (Sched_Lock);

               if not Write_Res.Success then
                  return Set_Mutation_Error
                    (Result, "Failed to append scheduled obligation: " &
                             Write_Res.Error_Reason (1 .. Write_Res.Error_Len));
               end if;

               Result.Success    := True;
               Result.Target_Len := Next_Id_Str'Length;
               Result.Target_Str (1 .. Next_Id_Str'Length) := Next_Id_Str;
               return Result;
            end;
         end;
      end;
   end Add_Scheduled_Obligation;

   function Retire_Scheduled_Obligation
     (Scheduled_Path : String;
      Target_Id      : Scheduled_Id) return Scheduled_Mutation_Result
   is
      Result          : Scheduled_Mutation_Result;
      Target_Str      : constant String := Target_Id.Token.Value (1 .. Target_Id.Token.Length);
      Sched_Lock_Path : constant String := Scheduled_Path & ".loam-writer-lock";
      Sched_Lock      : Lock_Handle;

      Read_Res : constant Read_Scheduled_Result :=
        Read_Scheduled_File (Scheduled_Path);
   begin
      if not Read_Res.Success then
         return Set_Mutation_Error
           (Result, "Failed to read scheduled file: " &
                    Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
      end if;

      declare
         Lookup : constant Lookup_Result :=
           Find_Occurrence (Read_Res.Lifecycle, Target_Id);
      begin
         if not Lookup.Found then
            return Set_Mutation_Error (Result, "Scheduled occurrence not found: " & Target_Str);
         end if;

         if not Is_Current_Open (Read_Res.Lifecycle, Target_Id) then
            return Set_Mutation_Error (Result, "Scheduled occurrence is not current-open: " & Target_Str);
         end if;

         if not Acquire_Exclusive_Lock (Sched_Lock_Path, Sched_Lock) then
            return Set_Mutation_Error (Result, "Failed to acquire scheduled lifecycle lock");
         end if;

         declare
            Write_Res : constant Write_Scheduled_Result :=
              Append_Retirement
                (Scheduled_Path => Scheduled_Path,
                 Target         => Target_Id);
         begin
            Release_Lock (Sched_Lock);

            if not Write_Res.Success then
               return Set_Mutation_Error
                 (Result, "Failed to append retirement: " &
                          Write_Res.Error_Reason (1 .. Write_Res.Error_Len));
            end if;

            Result.Success    := True;
            Result.Target_Len := Target_Str'Length;
            Result.Target_Str (1 .. Target_Str'Length) := Target_Str;
            return Result;
         end;
      end;
   end Retire_Scheduled_Obligation;

end HRA_N.Application.Scheduled_Publisher;
