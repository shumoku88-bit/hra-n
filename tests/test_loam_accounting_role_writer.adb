with Ada.Directories;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types;           use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Accounting_Role_Writer;
use HRA_N.Storage.Loam_Accounting_Role_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Accounting_Role_Writer is

   use type Role_Publish_Status;

   Root : constant String := "/tmp/hra_n_loam_accounting_role_writer_test";
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
      Empty_Locus_Admission : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL;
      Admitted_Locus : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL &
        "LOCUS" & HT & "wallet" & NL;
      Empty_Roles : constant String :=
        "LOAM-ACCOUNTING-ROLE-MAP" & HT & "1" & NL;

      Draft_Wallet : constant Role_Draft :=
        (Locus => (Token => Make_Token ("wallet")),
         Role  => Role_Asset);
      Draft_Wallet_Updated : constant Role_Draft :=
        (Locus => (Token => Make_Token ("wallet")),
         Role  => Role_Expense);
   begin
      Reset_Root;

      --  1. Invalid root directory
      declare
         Res : constant Publish_Result := Publish_Role ("", Draft_Wallet);
      begin
         Assert (not Res.Success, "empty root fails");
         Assert (Res.Status = Invalid_Root_Directory, "status is Invalid_Root_Directory");
         Assert (Format_Error (Res)'Length > 0, "Format_Error non-empty");
      end;

      --  2. Empty locus
      declare
         Bad_Draft : constant Role_Draft :=
           (Locus => (Token => (Length => 0, Value => [others => ' '])),
            Role  => Role_Asset);
         Res : constant Publish_Result := Publish_Role (Root, Bad_Draft);
      begin
         Assert (not Res.Success, "empty locus fails");
         Assert (Res.Status = Empty_Locus, "status is Empty_Locus");
      end;

      --  3. Locus_Admission_Missing
      declare
         Res : constant Publish_Result := Publish_Role (Root, Draft_Wallet);
      begin
         Assert (not Res.Success, "missing locus-admission.loam fails");
         Assert (Res.Status = Locus_Admission_Missing, "status is Locus_Admission_Missing");
      end;

      --  4. Locus_Admission_Read_Error
      Write_Fixture ("locus-admission.loam", "CORRUPT_BYTES" & NL);
      declare
         Res : constant Publish_Result := Publish_Role (Root, Draft_Wallet);
      begin
         Assert (not Res.Success, "corrupt locus admission fails");
         Assert (Res.Status = Locus_Admission_Read_Error, "status is Locus_Admission_Read_Error");
      end;

      --  5. Locus_Not_Admitted
      Write_Fixture ("locus-admission.loam", Empty_Locus_Admission);
      declare
         Res : constant Publish_Result := Publish_Role (Root, Draft_Wallet);
      begin
         Assert (not Res.Success, "unadmitted locus fails");
         Assert (Res.Status = Locus_Not_Admitted, "status is Locus_Not_Admitted");
      end;

      --  6. Cannot_Read_File (accounting-role.loam missing)
      Write_Fixture ("locus-admission.loam", Admitted_Locus);
      declare
         Res : constant Publish_Result := Publish_Role (Root, Draft_Wallet);
      begin
         Assert (not Res.Success, "missing accounting-role.loam fails");
         Assert (Res.Status = Cannot_Read_File, "status is Cannot_Read_File");
      end;

      --  7. Corrupt_Existing_File
      Write_Fixture ("accounting-role.loam", "CORRUPT_ROLE_BYTES" & NL);
      declare
         Res : constant Publish_Result := Publish_Role (Root, Draft_Wallet);
      begin
         Assert (not Res.Success, "corrupt accounting role file fails");
         Assert (Res.Status = Corrupt_Existing_File, "status is Corrupt_Existing_File");
      end;

      --  8. Successful initial assignment
      Write_Fixture ("accounting-role.loam", Empty_Roles);
      declare
         Res : constant Publish_Result := Publish_Role (Root, Draft_Wallet);
      begin
         Assert (Res.Success, "role assignment succeeds");
         Assert (Format_Error (Res) = "", "Format_Error empty on success");
      end;

      --  9. Update existing role assignment
      declare
         Res : constant Publish_Result := Publish_Role (Root, Draft_Wallet_Updated);
      begin
         Assert (Res.Success, "role assignment update succeeds");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Accounting_Role_Writer;
