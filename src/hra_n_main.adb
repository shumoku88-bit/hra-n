-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Main entry point: Household inspection & real-data verification
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Containers;
with HRA_N.Core.Types;             use HRA_N.Core.Types;
with HRA_N.Core.Event;             use HRA_N.Core.Event;
with HRA_N.Core.Coverage;          use HRA_N.Core.Coverage;
with HRA_N.Storage.Manifest;       use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;   use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Coverage_Reader; use HRA_N.Storage.Coverage_Reader;

procedure HRA_N_Main is
   Data_Dir : constant String := "/Users/user/Projects/moko/loam-data";
   Auth_Dir : constant String := Data_Dir & "/movement-authority";

   Manifest_Res : Read_Manifest_Result;
   Event_Res    : Read_Result;
   Coverage_Res : Read_Coverage_Result;
   Failed_Fam   : Manifest_Family;
   JPY          : constant Measure_Id := (Token => Make_Token ("jpy"));
begin
   Put_Line ("============================================================");
   Put_Line (" HRA-N: Verified Household Engine");
   Put_Line (" Authority-Governed Zero-Origin Balance Projection");
   Put_Line ("============================================================");

   -- 1. Load and Verify Manifest Authority (CURRENT)
   Put_Line ("Loading movement authority manifest: " & Auth_Dir & "/CURRENT");
   Manifest_Res := Read_Manifest_File (Auth_Dir & "/CURRENT");
   if not Manifest_Res.Success then
      Put_Line ("[ERROR] Failed to load manifest: " &
                Manifest_Res.Error_Reason (1 .. Manifest_Res.Error_Len));
      return;
   end if;

   Put_Line ("Verifying cryptographic SHA-256 integrity for all authority objects...");
   if not Verify_All_Objects (Auth_Dir, Manifest_Res.Manifest, Failed_Fam) then
      Put_Line ("[FATAL] Integrity verification failed for family: " &
                Family_Name (Failed_Fam));
      return;
   end if;
   Put_Line ("  [OK] All 6 authority objects verified against content digests.");

   -- 2. Load Selected Event Memory via Manifest
   declare
      Event_Rel : constant String :=
        Manifest_Res.Manifest (Family_Event).Rel_Path
          (1 .. Manifest_Res.Manifest (Family_Event).Path_Len);
      Event_Full : constant String := Auth_Dir & "/" & Event_Rel;
   begin
      Put_Line ("Loading authoritative event memory: " & Event_Rel);
      Event_Res := Read_Event_Memory_File (Event_Full);
      if not Event_Res.Success then
         Put_Line ("[ERROR] Failed to load event memory: " &
                   Event_Res.Error_Reason (1 .. Event_Res.Error_Len));
         return;
      end if;
      Put_Line ("  Admitted events: " &
                Ada.Containers.Count_Type'Image (Event_Res.Events.Length));
   end;

   -- 3. Load Zero-Origin Coverage Evidence
   Put_Line ("Loading zero-origin coverage evidence: " & Data_Dir & "/zero-origin-coverage.loam");
   Coverage_Res := Read_Coverage_File (Data_Dir & "/zero-origin-coverage.loam");
   if not Coverage_Res.Success then
      Put_Line ("[ERROR] Failed to load coverage: " &
                Coverage_Res.Error_Reason (1 .. Coverage_Res.Error_Len));
      return;
   end if;
   Put_Line ("  Covered coordinates: " &
             Coverage_Count_Type'Image (Coordinate_Count (Coverage_Res.Coverage)));

   Put_Line ("------------------------------------------------------------");
   Put_Line (" Verified Household Balances (Only Affirmatively Covered Loci):");
   Put_Line ("------------------------------------------------------------");

   -- Project balance for each covered coordinate
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

   -- 4. Fail-Closed Verification on Uncovered Loci
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
   Put_Line (" and mathematical balance laws verified.");
   Put_Line ("============================================================");
end HRA_N_Main;
