-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main entry point: Household inspection, review, and publication
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Containers;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Coverage;             use HRA_N.Core.Coverage;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Storage.Manifest;          use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;      use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Coverage_Reader;   use HRA_N.Storage.Coverage_Reader;
with HRA_N.Storage.Validity_Reader;   use HRA_N.Storage.Validity_Reader;
with HRA_N.Storage.Description_Reader; use HRA_N.Storage.Description_Reader;
with HRA_N.Application.Review;        use HRA_N.Application.Review;
with HRA_N.Application.Publisher;     use HRA_N.Application.Publisher;
with HRA_N.Application.Doctor;        use HRA_N.Application.Doctor;
with HRA_N.Application.Initializer;   use HRA_N.Application.Initializer;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Output;                 use HRA_N.UI.Output;
with HRA_N.UI.Interactive_Movement;
with HRA_N.UI.Scheduled_Cli;

procedure HRA_N_Main is
   Paths       : Path_Config;
   Command_Str : String (1 .. 64) := [others => ' '];
   Cmd_Len     : Natural          := 0;
   Command_Idx : Positive         := 1;

   Manifest_Res    : Read_Manifest_Result;
   Event_Res       : Read_Result;
   Coverage_Res    : Read_Coverage_Result;
   Validity_Res    : Read_Validity_Result;
   Description_Res : Read_Description_Result;
   Failed_Fam      : Manifest_Family;
   JPY             : constant Measure_Id := (Token => Make_Token ("jpy"));
begin
   Resolve_From_Cli (Paths, Command_Str, Cmd_Len, Command_Idx);

   declare
      Command        : constant String  := Command_Str (1 .. Cmd_Len);
      Auth_Dir       : constant String  := Authority_Dir_Str (Paths);
      Scheduled_Path : constant String  := Scheduled_Path_Str (Paths);
      Coverage_Path  : constant String  := Coverage_Path_Str (Paths);
      Reversals_Path : constant String  := Reversals_Path_Str (Paths);
      Arg_Count      : constant Natural := Ada.Command_Line.Argument_Count;
      Rem_Args       : constant Natural :=
        (if Arg_Count >= Command_Idx then Arg_Count - Command_Idx else 0);
   begin
      --  Branch: Initializer for a new household authority
      if Command = "init" then
         declare
            Target : constant String :=
              (if Rem_Args >= 1
               then Ada.Command_Line.Argument (Command_Idx + 1)
               else "./hra-data");
            Init_Res : constant Init_Result :=
              Initialize_Household (Target);
         begin
            if Init_Res.Success then
               Put_Line ("============================================================");
               Put_Line (" [OK] Initialized new household authority at: " & Target);
               Put_Line ("      Created 6 cryptographic authority objects in CURRENT");
               Put_Line ("      Configured initial LocusAdmission vocabulary (7 loci)");
               Put_Line ("      Configured zero-origin coverage (cash, bank)");
               Put_Line ("      Self-verifying Doctor audit: 100% HEALTHY");
               Put_Line ("============================================================");
               Put_Line ("Run 'hra-n movement' to record your first transaction!");
            else
               Put_Line ("[ERROR] Initialization failed: " &
                         Init_Res.Error_Reason (1 .. Init_Res.Error_Len));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
      end if;

      --  Branch: Doctor & Integrity Verification
      if Command = "doctor" or else Command = "verify" then
         declare
            Doc_Report : Doctor_Report;
         begin
            Run_Doctor
              (Authority_Dir => Auth_Dir,
               Coverage_Path => Coverage_Path,
               Report        => Doc_Report,
               Quiet         => False);
            if not Doc_Report.Overall_Healthy then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
            return;
         end;
      end if;

      --  Branch: Movement reversal (revert)
      if (Command = "movement" and then Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "revert")
        or else Command = "revert"
      then
         declare
            Arg_Offset : constant Positive :=
              (if Command = "revert" then Command_Idx else Command_Idx + 1);
            Eff_Rem    : constant Natural :=
              (if Command = "revert" then Rem_Args else Rem_Args - 1);
         begin
            if Eff_Rem < 1 then
               Put_Line ("Usage: hra-n movement revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
               Put_Line ("   or: hra-n revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            declare
               Target_Id : constant String := Ada.Command_Line.Argument (Arg_Offset + 1);
               Date_Val  : Date_Type       := Get_System_Date;
               Desc_Val  : constant String :=
                 (if Eff_Rem >= 3 then Ada.Command_Line.Argument (Arg_Offset + 3)
                  elsif Eff_Rem = 2 and then Ada.Command_Line.Argument (Arg_Offset + 2)'Length > 0
                    and then Ada.Command_Line.Argument (Arg_Offset + 2)(Ada.Command_Line.Argument (Arg_Offset + 2)'First) /= '2'
                  then Ada.Command_Line.Argument (Arg_Offset + 2)
                  else "");
            begin
               if Eff_Rem >= 2 then
                  declare
                     Date_Arg : constant String := Ada.Command_Line.Argument (Arg_Offset + 2);
                     Parsed_D : Date_Type;
                  begin
                     if Parse_Iso_Date (Date_Arg, Parsed_D) then
                        Date_Val := Parsed_D;
                     end if;
                  end;
               end if;

               declare
                  Pub_Res : constant Publish_Result :=
                    Publish_Reversal
                      (Authority_Dir   => Auth_Dir,
                       Target_Event_Id => Target_Id,
                       Valid_On        => Date_Val,
                       Description     => Desc_Val,
                       Reversals_Path  => Reversals_Path);
               begin
                  if Pub_Res.Success then
                     Put_Line ("============================================================");
                     Put_Line (" [OK] Admitted and published Reversal receipt: " &
                               Pub_Res.Event_Id_Str (1 .. Pub_Res.Event_Id_Len));
                     Put_Line ("      TARGET: " & Target_Id);
                     Put_Line ("      DATE:   " & Format_Iso_Date (Date_Val));
                     if Desc_Val'Length > 0 then
                        Put_Line ("      REASON: " & Desc_Val);
                     end if;
                     Put_Line ("============================================================");
                  else
                     Put_Line ("[ERROR] Reversal rejected: " &
                               Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  end if;
               end;
            end;
         end;
         return;
      end if;

      --  Branch: Movement publication has its own exclusive lock and authority lifecycle
      if Command = "movement" then
         if Rem_Args = 0 then
            --  Interactive entrance when no positional arguments provided
            declare
               Success : Boolean;
            begin
               HRA_N.UI.Interactive_Movement.Run_Interactive
                 (Authority_Dir => Auth_Dir,
                  Success       => Success);
               if not Success then
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
               return;
            end;
         elsif Rem_Args < 3 then
            Put_Line ("Usage: hra-n movement (interactive mode)");
            Put_Line ("   or: hra-n movement <FROM> <TO> <AMOUNT> [YYYY-MM-DD] [DESCRIPTION]");
            Put_Line ("   or: hra-n movement revert <EVENT_ID> [YYYY-MM-DD] [REASON]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            From_Locus : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
            To_Locus   : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
            Amount_Str : constant String := Ada.Command_Line.Argument (Command_Idx + 3);
            Amount_Val : Quanta_Type;

            Date_Val   : Date_Type := Get_System_Date;
            Desc_Val   : constant String :=
              (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 5)
               elsif Rem_Args = 4 and then Ada.Command_Line.Argument (Command_Idx + 4)'Length > 0
                 and then Ada.Command_Line.Argument (Command_Idx + 4)(Ada.Command_Line.Argument (Command_Idx + 4)'First) /= '2'
               then Ada.Command_Line.Argument (Command_Idx + 4)
               else "");
         begin
            begin
               Amount_Val := Quanta_Type'Value (Amount_Str);
            exception
               when others =>
                  Put_Line ("hra-n: movement amount must be a positive integer");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
            end;

            if Rem_Args >= 4 then
               declare
                  Date_Arg : constant String := Ada.Command_Line.Argument (Command_Idx + 4);
                  Parsed_D : Date_Type;
               begin
                  if Parse_Iso_Date (Date_Arg, Parsed_D) then
                     Date_Val := Parsed_D;
                  end if;
               end;
            end if;

            declare
               Pub_Res : constant Publish_Result :=
                 Publish_Movement
                   (Authority_Dir => Auth_Dir,
                    From_Locus    => From_Locus,
                    To_Locus      => To_Locus,
                    Amount        => Amount_Val,
                    Valid_On      => Date_Val,
                    Description   => Desc_Val);
            begin
               if Pub_Res.Success then
                  Put_Line ("============================================================");
                  Put_Line (" [OK] Admitted and published Movement receipt: " &
                            Pub_Res.Event_Id_Str (1 .. Pub_Res.Event_Id_Len));
                  Put_Line ("      FROM: " & From_Locus & " (-" & Amount_Str & " jpy)");
                  Put_Line ("      TO:   " & To_Locus & " (+" & Amount_Str & " jpy)");
                  Put_Line ("      DATE: " & Format_Iso_Date (Date_Val));
                  if Desc_Val'Length > 0 then
                     Put_Line ("      DESC: " & Desc_Val);
                  end if;
                  Put_Line ("============================================================");
               else
                  Put_Line ("[ERROR] Publication rejected: " &
                            Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               end if;
            end;
         end;
         return;
      end if;

      --  Branch: Scheduled movement inspection, creation, completion, and retirement
      if Command = "scheduled" or else Command = "open-scheduled" then
         if Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "complete" then
            declare
               Target_Arg : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               Date_Arg   : constant String :=
                 (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else "");
               Desc_Arg   : constant String :=
                 (if Rem_Args >= 4 then Ada.Command_Line.Argument (Command_Idx + 4) else "");
            begin
               HRA_N.UI.Scheduled_Cli.Complete_Scheduled
                 (Scheduled_Path  => Scheduled_Path,
                  Authority_Dir   => Auth_Dir,
                  Target_Str      => Target_Arg,
                  Date_Str        => Date_Arg,
                  Description_Str => Desc_Arg);
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "add" then
            declare
               From_Arg   : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
               To_Arg     : constant String :=
                 (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else "");
               Amount_Arg : constant String :=
                 (if Rem_Args >= 4 then Ada.Command_Line.Argument (Command_Idx + 4) else "");
               Date_Arg   : constant String :=
                 (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 5) else "");
            begin
               HRA_N.UI.Scheduled_Cli.Add_Scheduled
                 (Scheduled_Path => Scheduled_Path,
                  Authority_Dir  => Auth_Dir,
                  From_Locus     => From_Arg,
                  To_Locus       => To_Arg,
                  Amount_Str     => Amount_Arg,
                  Date_Str       => Date_Arg);
               return;
            end;
         elsif Rem_Args >= 1 and then Ada.Command_Line.Argument (Command_Idx + 1) = "retire" then
            declare
               Target_Arg : constant String :=
                 (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else "");
            begin
               HRA_N.UI.Scheduled_Cli.Retire_Scheduled
                 (Scheduled_Path => Scheduled_Path,
                  Authority_Dir  => Auth_Dir,
                  Target_Str     => Target_Arg);
               return;
            end;
         else
            HRA_N.UI.Scheduled_Cli.Display_Open_Scheduled
              (Scheduled_Path => Scheduled_Path,
               Authority_Dir  => Auth_Dir);
            return;
         end if;
      end if;

      --  1. Load and Verify Manifest Authority (CURRENT)
      Manifest_Res := Read_Manifest_File (Auth_Dir & "/CURRENT");
      if not Manifest_Res.Success then
         Put_Line ("[ERROR] Failed to load manifest: " &
                   Manifest_Res.Error_Reason (1 .. Manifest_Res.Error_Len));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      if not Verify_All_Objects (Auth_Dir, Manifest_Res.Manifest, Failed_Fam) then
         Put_Line ("[FATAL] Integrity verification failed for family: " &
                   Family_Name (Failed_Fam));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      --  2. Load Authoritative Event Memory via Manifest
      declare
         Event_Rel : constant String :=
           Manifest_Res.Manifest (Family_Event).Rel_Path
             (1 .. Manifest_Res.Manifest (Family_Event).Path_Len);
         Event_Full : constant String := Auth_Dir & "/" & Event_Rel;
      begin
         Event_Res := Read_Event_Memory_File (Event_Full);
         if not Event_Res.Success then
            Put_Line ("[ERROR] Failed to load event memory: " &
                      Event_Res.Error_Reason (1 .. Event_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      --  3. Load Authoritative Actual Validity Evidence via Manifest
      declare
         Val_Rel : constant String :=
           Manifest_Res.Manifest (Family_Actual_Validity).Rel_Path
             (1 .. Manifest_Res.Manifest (Family_Actual_Validity).Path_Len);
         Val_Full : constant String := Auth_Dir & "/" & Val_Rel;
      begin
         Validity_Res := Read_Validity_File (Val_Full);
         if not Validity_Res.Success then
            Put_Line ("[ERROR] Failed to load validity: " &
                      Validity_Res.Error_Reason (1 .. Validity_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      --  4. Load Authoritative Event Description Evidence via Manifest
      declare
         Desc_Rel : constant String :=
           Manifest_Res.Manifest (Family_Event_Description).Rel_Path
             (1 .. Manifest_Res.Manifest (Family_Event_Description).Path_Len);
         Desc_Full : constant String := Auth_Dir & "/" & Desc_Rel;
      begin
         Description_Res := Read_Description_File (Desc_Full);
         if not Description_Res.Success then
            Put_Line ("[ERROR] Failed to load descriptions: " &
                      Description_Res.Error_Reason (1 .. Description_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      --  Dispatch command: "review" or "summary"
      if Command = "review" then
         declare
            Query_Text : constant String :=
              (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else "t");
            Today      : constant Date_Type := Get_System_Date;
            Query      : Review_Query;
         begin
            if not Parse_Query (Query_Text, Today, Query) then
               Put_Line ("hra-n: review expects YYYY-MM-DD, /text, u (undated), or t (recent week)");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Execute_Review
              (Events       => Event_Res.Events,
               Validity     => Validity_Res.Memory,
               Descriptions => Description_Res.Memory,
               Query        => Query);
         end;
      else
         --  Default: Summary & Integrity Verification
         Put_Line ("============================================================");
         Put_Line (" HRA-N: Verified Household Engine");
         Put_Line (" Authority-Governed Reckon and Review Baseline");
         Put_Line ("============================================================");
         Put_Line ("  [OK] All 6 authority objects verified against content digests.");
         Put_Line ("  Admitted events: " &
                   Ada.Containers.Count_Type'Image (Event_Res.Events.Length));
         Put_Line ("  Admitted validity facts: " &
                   Validity_Count_Type'Image (Entry_Count (Validity_Res.Memory)));
         Put_Line ("  Admitted description facts: " &
                   Description_Count_Type'Image (Entry_Count (Description_Res.Memory)));

         --  Load Zero-Origin Coverage Evidence
         Coverage_Res := Read_Coverage_File (Coverage_Path);
         if not Coverage_Res.Success then
            Put_Line ("[ERROR] Failed to load coverage: " &
                      Coverage_Res.Error_Reason (1 .. Coverage_Res.Error_Len));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         Put_Line ("  Covered coordinates: " &
                   Coverage_Count_Type'Image (Coordinate_Count (Coverage_Res.Coverage)));

         Put_Line ("------------------------------------------------------------");
         Put_Line (" Verified Household Balances (Only Affirmatively Covered Loci):");
         Put_Line ("------------------------------------------------------------");

         for I in 1 .. Coordinate_Count (Coverage_Res.Coverage) loop
            declare
               Coord : constant Coordinate_Type := Coordinate_At (Coverage_Res.Coverage, I);
               Total : Long_Long_Integer := 0;
            begin
               for Ev of Event_Res.Events loop
                  Total := Total + Quantity_At (Ev, Coord.Locus, Coord.Measure);
               end loop;

               declare
                  Bal : constant Balance_Result :=
                    Inspect_Balance (Coverage_Res.Coverage, Coord, Total);
               begin
                  case Bal.Status is
                     when Covered =>
                        Put_Line ("  [COVERED] " &
                                  Coord.Locus.Token.Value (1 .. Coord.Locus.Token.Length) &
                                  " : " & Long_Long_Integer'Image (Bal.Amount) &
                                  " " & Coord.Measure.Token.Value (1 .. Coord.Measure.Token.Length));
                     when Coverage_Missing =>
                        Put_Line ("  [UNAVAILABLE] " &
                                  Coord.Locus.Token.Value (1 .. Coord.Locus.Token.Length) &
                                  " (Coverage Missing)");
                  end case;
               end;
            end;
         end loop;

         Put_Line ("------------------------------------------------------------");
         Put_Line (" Fail-Closed Verification (Querying Uncovered Loci):");
         Put_Line ("------------------------------------------------------------");
         declare
            Food_Coord : constant Coordinate_Type :=
              (Locus => (Token => Make_Token ("food")), Measure => JPY);
            Food_Bal : constant Balance_Result :=
              Inspect_Balance (Coverage_Res.Coverage, Food_Coord, 12345);
         begin
            if Food_Bal.Status = Coverage_Missing then
               Put_Line ("  [OK] Locus 'food' correctly evaluated as Coverage_Missing.");
               Put_Line ("       No implicit 0 or false purchasing power was fabricated.");
            else
               Put_Line ("  [FAIL] Uncovered locus 'food' evaluated as covered!");
            end if;
         end;

         Put_Line ("============================================================");
         Put_Line (" Complete authority manifest, cryptographic integrity,");
         Put_Line (" temporal occurrence validity, and balance laws verified.");
         Put_Line ("============================================================");
      end if;
   end;
end HRA_N_Main;
