with Ada.Directories;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Capacity_Writer;
use HRA_N.Storage.Loam_Capacity_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Capacity_Writer is

   use type Capacity_Publish_Status;

   Root : constant String := "/tmp/hra_n_loam_capacity_writer_test";

   procedure Reset_Root is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
   end Reset_Root;

   procedure Run is
      Unalloc : constant Capacity_Coordinate := Make_Unallocated_Coordinate;
      Food    : constant Capacity_Coordinate :=
        Make_Purpose_Coordinate (Make_Token ("Food"));
      Rent    : constant Capacity_Coordinate :=
        Make_Purpose_Coordinate (Make_Token ("Rent"));
      Good_Date : constant Date_Type := (Year => 2026, Month => 9, Day => 25);
   begin
      Reset_Root;

      --  1. Invalid root directory
      declare
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Good_Date);
         Res : constant Publish_Result := Publish_Capacity ("", Draft);
      begin
         Assert (not Res.Success, "empty root fails");
         Assert (Res.Status = Invalid_Root_Directory, "status is Invalid_Root_Directory");
         Assert (Format_Error (Res)'Length > 0, "Format_Error is non-empty");
      end;

      declare
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Good_Date);
         Res : constant Publish_Result :=
           Publish_Capacity (Root & "/nonexistent_sub_dir", Draft);
      begin
         Assert (not Res.Success, "nonexistent root fails");
         Assert (Res.Status = Invalid_Root_Directory, "status is Invalid_Root_Directory");
      end;

      --  2. Empty changes
      declare
         Draft : Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Good_Date);
         Res : Publish_Result;
      begin
         Draft.Change_Count := 0;
         Res := Publish_Capacity (Root, Draft);
         Assert (not Res.Success, "empty changes fails");
         Assert (Res.Status = Empty_Changes, "status is Empty_Changes");
      end;

      --  3. Invalid date
      declare
         Bad_Date : constant Date_Type := (Year => 2026, Month => 2, Day => 29);
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Bad_Date);
         Res : constant Publish_Result := Publish_Capacity (Root, Draft);
      begin
         Assert (not Res.Success, "invalid date fails");
         Assert (Res.Status = Invalid_Date, "status is Invalid_Date");
      end;

      --  4. Unsupported currency
      declare
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Good_Date, Make_Token ("usd"));
         Res : constant Publish_Result := Publish_Capacity (Root, Draft);
      begin
         Assert (not Res.Success, "unsupported currency fails");
         Assert (Res.Status = Unsupported_Currency, "status is Unsupported_Currency");
      end;

      --  5. Zero amount
      declare
         Draft : Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Good_Date);
         Res : Publish_Result;
      begin
         Draft.Changes (1).Amount := 0;
         Draft.Changes (2).Amount := 0;
         Res := Publish_Capacity (Root, Draft);
         Assert (not Res.Success, "zero amount fails");
         Assert (Res.Status = Zero_Amount, "status is Zero_Amount");
      end;

      --  6. Invalid purpose token
      declare
         Bad_Coord : constant Capacity_Coordinate :=
           Make_Purpose_Coordinate (Make_Token ("Fo" & ASCII.HT & "od"));
         Draft : Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Bad_Coord, 1000, Good_Date);
         Res : Publish_Result;
      begin
         Res := Publish_Capacity (Root, Draft);
         Assert (not Res.Success, "invalid purpose token fails");
         Assert (Res.Status = Invalid_Purpose_Token, "status is Invalid_Purpose_Token");
      end;

      --  7. Duplicate coordinate
      declare
         Draft : Capacity_Draft :=
           Make_Transfer_Draft (Food, Food, 1000, Good_Date);
         Res : Publish_Result;
      begin
         Res := Publish_Capacity (Root, Draft);
         Assert (not Res.Success, "duplicate coordinate fails");
         Assert (Res.Status = Duplicate_Coordinate, "status is Duplicate_Coordinate");
      end;

      --  8. Unbalanced changes
      declare
         Draft : Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Good_Date);
         Res : Publish_Result;
      begin
         Draft.Changes (1).Amount := -500;
         Draft.Changes (2).Amount := 1000;
         Res := Publish_Capacity (Root, Draft);
         Assert (not Res.Success, "unbalanced changes fails");
         Assert (Res.Status = Unbalanced_Changes, "status is Unbalanced_Changes");
      end;

      --  9. Successful initial publish
      declare
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 5000, Good_Date);
         Res : constant Publish_Result := Publish_Capacity (Root, Draft);
      begin
         Assert (Res.Success, "initial publish succeeds");
         Assert (Format_Error (Res) = "", "Format_Error empty on success");
         Assert (Res.Movement_Len > 0, "Movement_Len > 0");
         Assert
           (Res.Movement_Id (1 .. Res.Movement_Len) = "capacity-1",
            "first movement id is capacity-1");
      end;

      --  10. Second publish (subsequent ID sequence)
      declare
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Rent, 10000, Good_Date);
         Res : constant Publish_Result := Publish_Capacity (Root, Draft);
      begin
         Assert (Res.Success, "second publish succeeds");
         Assert
           (Res.Movement_Id (1 .. Res.Movement_Len) = "capacity-2",
            "second movement id is capacity-2");
      end;

      --  11. Negative entitlement check
      --  Food has 5000, trying to take 6000 from Food to Unalloc
      declare
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Food, Unalloc, 6000, Good_Date);
         Res : constant Publish_Result := Publish_Capacity (Root, Draft);
      begin
         Assert (not Res.Success, "negative entitlement fails");
         Assert (Res.Status = Negative_Entitlement, "status is Negative_Entitlement");
         Assert (Format_Error (Res)'Length > 0, "negative entitlement format error non-empty");
      end;

      --  12. Corrupt existing capacity.loam fails closed
      declare
         Err : String (1 .. 128) := [others => ' '];
         Err_Len : Natural := 0;
         Wrote : constant Boolean :=
           Write_File_Atomically
             (Root & "/capacity.loam", "CORRUPT_BYTES" & ASCII.LF, Err, Err_Len);
         Draft : constant Capacity_Draft :=
           Make_Transfer_Draft (Unalloc, Food, 1000, Good_Date);
         Res : Publish_Result;
      begin
         Assert (Wrote, "wrote corrupt fixture");
         Res := Publish_Capacity (Root, Draft);
         Assert (not Res.Success, "corrupt file rejects publish");
         Assert (Res.Status = Corrupt_Existing_File, "status is Corrupt_Existing_File");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Capacity_Writer;
