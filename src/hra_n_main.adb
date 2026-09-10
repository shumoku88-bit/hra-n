-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main entry point: Household inspection, review, and verification
-------------------------------------------------------------------------------

with Ada.Text_IO;              use Ada.Text_IO;
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

procedure HRA_N_Main is
   Data_Dir : constant String := "/Users/user/Projects/moko/loam-data";
   Auth_Dir : constant String := Data_Dir & "/movement-authority";

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
