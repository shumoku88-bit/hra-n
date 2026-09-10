-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Coverage
-------------------------------------------------------------------------------

with HRA_N.Core.Types;             use HRA_N.Core.Types;
with HRA_N.Core.Coverage;          use HRA_N.Core.Coverage;
with HRA_N.Storage.Coverage_Reader; use HRA_N.Storage.Coverage_Reader;
with Test_Support;                 use Test_Support;

package body Test_Coverage is

   procedure Run is
      JPY    : constant Measure_Id := (Token => Make_Token ("jpy"));
      Cash   : constant Locus_Id   := (Token => Make_Token ("cash"));
      Bank   : constant Locus_Id   := (Token => Make_Token ("bank"));
      Food   : constant Locus_Id   := (Token => Make_Token ("food"));

      Coord_Cash : constant Coordinate_Type := (Locus => Cash, Measure => JPY);
      Coord_Bank : constant Coordinate_Type := (Locus => Bank, Measure => JPY);
      Coord_Food : constant Coordinate_Type := (Locus => Food, Measure => JPY);

      Coords : Coordinate_List;
   begin
      -- Test 1: Coordinates uniqueness
      Coords.Count := 2;
      Coords.Values (1) := Coord_Cash;
      Coords.Values (2) := Coord_Bank;
      Assert (Coordinates_Are_Unique (Coords), "Unique coordinates accepted");

      Coords.Count := 3;
      Coords.Values (3) := Coord_Cash;  -- duplicate
      Assert (not Coordinates_Are_Unique (Coords), "Duplicate coordinates rejected");

      -- Test 2: Coverage inspection
      Coords.Count := 2;
      declare
         Cov : constant Zero_Origin_Coverage := Make_Coverage (Coords);
      begin
         Assert (Is_Covered (Cov, Coord_Cash), "Cash:JPY is covered");
         Assert (Is_Covered (Cov, Coord_Bank), "Bank:JPY is covered");
         Assert (not Is_Covered (Cov, Coord_Food), "Food:JPY is NOT covered (fail-closed)");

         -- Test 3: Balance inspection contract
         declare
            Bal_Covered   : constant Balance_Result := Inspect_Balance (Cov, Coord_Cash, 5000);
            Bal_Uncovered : constant Balance_Result := Inspect_Balance (Cov, Coord_Food, 5000);
         begin
            Assert (Bal_Covered.Status = Covered, "Covered coordinate returns Covered status");
            Assert_Equal_Int (5000, Bal_Covered.Amount, "Covered coordinate returns exact amount");

            Assert (Bal_Uncovered.Status = Coverage_Missing,
                    "Uncovered coordinate returns Coverage_Missing (never fabricated 0)");
         end;
      end;

      -- Test 4: Real coverage file loading
      declare
         Real_Path : constant String :=
           "/Users/user/Projects/moko/loam-data/zero-origin-coverage.loam";
         Res_Real : constant Read_Coverage_Result := Read_Coverage_File (Real_Path);
      begin
         Assert (Res_Real.Success, "Real zero-origin-coverage.loam loaded successfully");
         Assert_Equal_Int (5, Long_Long_Integer (Coordinate_Count (Res_Real.Coverage)),
                           "Loaded exact 5 covered coordinates from real data");
      end;
   end Run;

end Test_Coverage;
