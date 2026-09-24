with Ada.Directories;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Locus_Admission_Writer;
use HRA_N.Storage.Loam_Locus_Admission_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Locus_Admission_Writer is

   use type Locus_Publish_Status;

   Root : constant String := "/tmp/hra_n_loam_locus_admission_writer_test";
   HT   : constant String := [1 => ASCII.HT];
   NL   : constant String := [1 => ASCII.LF];

   procedure Reset_Root is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
   end Reset_Root;

   procedure Write_Fixture (Filename : String; Content : String) is
      Err     : String (1 .. 128) := [others => ' '];
      Err_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Root & "/" & Filename, Content, Err, Err_Len),
         "fixture wrote: " & Filename);
   end Write_Fixture;

   procedure Run is
      Empty_Admission : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL;
      Valid_Locus : constant Locus_Id :=
        (Token => Make_Token ("wallet"));
      Second_Locus : constant Locus_Id :=
        (Token => Make_Token ("bank-main"));
   begin
      Reset_Root;

      --  1. Invalid root directory
      declare
         Res : constant Publish_Result := Publish_Locus ("", Valid_Locus);
      begin
         Assert (not Res.Success, "empty root fails");
         Assert (Res.Status = Invalid_Root_Directory, "status is Invalid_Root_Directory");
         Assert (Format_Error (Res)'Length > 0, "Format_Error non-empty");
      end;

      declare
         Res : constant Publish_Result :=
           Publish_Locus (Root & "/nonexistent_dir", Valid_Locus);
      begin
         Assert (not Res.Success, "nonexistent root fails");
         Assert (Res.Status = Invalid_Root_Directory, "status is Invalid_Root_Directory");
      end;

      --  2. Invalid locus token (empty or with space/tab)
      declare
         Empty_Id : constant Locus_Id :=
           (Token => (Length => 0, Value => [others => ' ']));
         Res : constant Publish_Result := Publish_Locus (Root, Empty_Id);
      begin
         Assert (not Res.Success, "empty token fails");
         Assert (Res.Status = Invalid_Locus_Token, "status is Invalid_Locus_Token");
      end;

      declare
         Space_Id : constant Locus_Id :=
           (Token => Make_Token ("bad id"));
         Res : constant Publish_Result := Publish_Locus (Root, Space_Id);
      begin
         Assert (not Res.Success, "token with space fails");
         Assert (Res.Status = Invalid_Locus_Token, "status is Invalid_Locus_Token");
      end;

      --  3. Cannot_Read_File (file doesn't exist yet)
      declare
         Res : constant Publish_Result := Publish_Locus (Root, Valid_Locus);
      begin
         Assert (not Res.Success, "missing file fails");
         Assert (Res.Status = Cannot_Read_File, "status is Cannot_Read_File");
      end;

      --  4. Corrupt_Existing_File
      Write_Fixture ("locus-admission.loam", "CORRUPT_BYTES" & NL);
      declare
         Res : constant Publish_Result := Publish_Locus (Root, Valid_Locus);
      begin
         Assert (not Res.Success, "corrupt file rejects publish");
         Assert (Res.Status = Corrupt_Existing_File, "status is Corrupt_Existing_File");
      end;

      --  5. Successful admission on valid empty authority
      Write_Fixture ("locus-admission.loam", Empty_Admission);
      declare
         Res : constant Publish_Result := Publish_Locus (Root, Valid_Locus);
      begin
         Assert (Res.Success, "admission of first locus succeeds");
         Assert (Format_Error (Res) = "", "Format_Error is empty on success");
      end;

      --  6. Already_Admitted
      declare
         Res : constant Publish_Result := Publish_Locus (Root, Valid_Locus);
      begin
         Assert (not Res.Success, "duplicate admission fails");
         Assert (Res.Status = Already_Admitted, "status is Already_Admitted");
         Assert (Format_Error (Res)'Length > 0, "Already_Admitted Format_Error non-empty");
      end;

      --  7. Second admission succeeds
      declare
         Res : constant Publish_Result := Publish_Locus (Root, Second_Locus);
      begin
         Assert (Res.Success, "admission of second locus succeeds");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Locus_Admission_Writer;
