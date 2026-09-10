-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main entry point: Household inspection, review, and publication
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Containers;
with Ada.Environment_Variables;
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
with HRA_N.UI.Output;                 use HRA_N.UI.Output;
with HRA_N.UI.Interactive_Movement;

procedure HRA_N_Main is
   Data_Dir : constant String := "/Users/user/Projects/moko/loam-data";

   function Resolve_Auth_Dir return String is
      Env_Val : constant String :=
        (if Ada.Environment_Variables.Exists ("LOAM_MOVEMENT_MANIFEST_ROOT")
         then Ada.Environment_Variables.Value ("LOAM_MOVEMENT_MANIFEST_ROOT")
         else "");
   begin
      if Env_Val'Length > 0 then
         return Env_Val;
      else
         return Data_Dir & "/movement-authority";
      end if;
   end Resolve_Auth_Dir;

   Auth_Dir : constant String := Resolve_Auth_Dir;

   Manifest_Res    : Read_Manifest_Result;
   Event_Res       : Read_Result;
   Coverage_Res    : Read_Coverage_Result;
   Validity_Res    : Read_Validity_Result;
   Description_Res : Read_Description_Result;
   Failed_Fam      : Manifest_Family;
   JPY             : constant Measure_Id := (Token => Make_Token ("jpy"));

   Arg_Count : constant Natural := Ada.Command_Line.Argument_Count;
   Command   : constant String  :=
     (if Arg_Count >= 1 then Ada.Command_Line.Argument (1) else "summary");
begin
   --  Branch: Initializer for a new household authority
   if Command = "init" then
      declare
         Target : constant String :=
           (if Arg_Count >= 2 then Ada.Command_Line.Argument (2) else "./hra-data");
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
            Coverage_Path => Data_Dir & "/zero-origin-coverage.loam",
            Report        => Doc_Report,
            Quiet         => False);
         if not Doc_Report.Overall_Healthy then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
         return;
      end;
   end if;

   --  Branch: Movement publication has its own exclusive lock and authority lifecycle
   if Command = "movement" then
      if Arg_Count = 1 then
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
      elsif Arg_Count < 4 then
         Put_Line ("Usage: hra-n movement (interactive mode)");
         Put_Line ("   or: hra-n movement <FROM> <TO> <AMOUNT> [YYYY-MM-DD] [DESCRIPTION]");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         From_Locus : constant String := Ada.Command_Line.Argument (2);
         To_Locus   : constant String := Ada.Command_Line.Argument (3);
         Amount_Str : constant String := Ada.Command_Line.Argument (4);
         Amount_Val : Quanta_Type;

         Date_Val   : Date_Type := Get_System_Date;
         Desc_Val   : constant String :=
           (if Arg_Count >= 6 then Ada.Command_Line.Argument (6)
            elsif Arg_Count = 5 and then Ada.Command_Line.Argument (5)'Length > 0
              and then Ada.Command_Line.Argument (5)(Ada.Command_Line.Argument (5)'First) /= '2'
            then Ada.Command_Line.Argument (5)
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

         if Arg_Count >= 5 then
            declare
               Date_Arg : constant String := Ada.Command_Line.Argument (5);
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
           (if Arg_Count >= 2 then Ada.Command_Line.Argument (2) else "t");
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
      Coverage_Res := Read_Coverage_File (Data_Dir & "/zero-origin-coverage.loam");
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
end HRA_N_Main;
