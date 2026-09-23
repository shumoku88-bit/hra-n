with Ada.Directories;
with HRA_N.Application.Canonical_Authority;
use HRA_N.Application.Canonical_Authority;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with Test_Support; use Test_Support;

package body Test_Canonical_Authority is

   Root      : constant String := "/tmp/hra_n_canonical_authority_test";
   Actual    : constant String := Root & "/actual.loam";
   Scheduled : constant String := Root & "/scheduled.loam";
   Policy    : constant String := Root & "/locus-admission.loam";

   procedure Write_Fixture (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "fixture file writes atomically: " & Path);
   end Write_Fixture;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      --  1. Empty root: canonical authority false
      Assert
        (not Canonical_Authority_Present (Root),
         "empty root must not claim canonical authority");

      --  2. Nonexistent directory: conservative false
      Assert
        (not Canonical_Authority_Present (Root & "/nonexistent_dir"),
         "nonexistent root must conservatively return false");

      --  3. actual.loam only: canonical authority true
      Write_Fixture (Actual, "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF);
      Assert
        (Canonical_Authority_Present (Root),
         "actual.loam only must claim canonical authority");
      Ada.Directories.Delete_File (Actual);
      Assert
        (not Canonical_Authority_Present (Root),
         "deletion of actual.loam reverts to no canonical authority");

      --  4. scheduled.loam only: canonical authority true
      Write_Fixture (Scheduled, "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" & ASCII.LF);
      Assert
        (Canonical_Authority_Present (Root),
         "scheduled.loam only must claim canonical authority");
      Ada.Directories.Delete_File (Scheduled);
      Assert
        (not Canonical_Authority_Present (Root),
         "deletion of scheduled.loam reverts to no canonical authority");

      --  5. locus-admission.loam only: canonical authority true
      Write_Fixture
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF);
      Assert
        (Canonical_Authority_Present (Root),
         "locus-admission.loam only must claim canonical authority");
      Ada.Directories.Delete_File (Policy);
      Assert
        (not Canonical_Authority_Present (Root),
         "deletion of locus-admission.loam reverts to no canonical authority");

      --  6. All markers present: canonical authority true
      Write_Fixture (Actual, "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF);
      Write_Fixture (Scheduled, "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" & ASCII.LF);
      Write_Fixture
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & ASCII.HT & "1" & ASCII.LF);
      Assert
        (Canonical_Authority_Present (Root),
         "all canonical markers present must claim canonical authority");

      --  7. Partial presence (pair: actual + policy): canonical authority true
      Ada.Directories.Delete_File (Scheduled);
      Assert
        (Canonical_Authority_Present (Root),
         "partial presence (actual + policy) selects canonical route");

      --  Cleanup
      Ada.Directories.Delete_Tree (Root);
   end Run;

end Test_Canonical_Authority;
