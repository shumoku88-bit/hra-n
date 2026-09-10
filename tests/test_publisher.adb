-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Movement Publication Implementation
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Containers;
with GNAT.OS_Lib;

use type Ada.Containers.Count_Type;

with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Storage.Manifest;          use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;      use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Validity_Reader;   use HRA_N.Storage.Validity_Reader;
with HRA_N.Storage.Description_Reader; use HRA_N.Storage.Description_Reader;
with HRA_N.Application.Publisher;     use HRA_N.Application.Publisher;
with HRA_N.Application.Doctor;        use HRA_N.Application.Doctor;
with HRA_N.Storage.Actual_Reversal_Reader;
with HRA_N.Core.Actual_Reversal;      use HRA_N.Core.Actual_Reversal;
with Ada.Text_IO;                    use Ada.Text_IO;
with Test_Support;                    use Test_Support;

package body Test_Publisher is

   Sandbox_Dir : constant String := "/tmp/hra_n_test_authority";
   function Source_Dir return String is (Real_Data_Dir & "/movement-authority");

   procedure Setup_Sandbox is
      Success : Boolean;
      Args    : GNAT.OS_Lib.Argument_List (1 .. 4);
   begin
      if Ada.Directories.Exists (Sandbox_Dir) then
         Args (1) := new String'("-rf");
         Args (2) := new String'(Sandbox_Dir);
         GNAT.OS_Lib.Spawn
           (Program_Name => "/bin/rm",
            Args         => Args (1 .. 2),
            Success      => Success);
         GNAT.OS_Lib.Free (Args (1));
         GNAT.OS_Lib.Free (Args (2));
      end if;

      Ada.Directories.Create_Path (Sandbox_Dir);

      Args (1) := new String'("-R");
      Args (2) := new String'(Source_Dir & "/");
      Args (3) := new String'(Sandbox_Dir & "/");
      GNAT.OS_Lib.Spawn
        (Program_Name => "/bin/cp",
         Args         => Args (1 .. 3),
         Success      => Success);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      GNAT.OS_Lib.Free (Args (3));
   end Setup_Sandbox;

   procedure Run is
      Res : Publish_Result;
      D   : constant Date_Type := Make_Date (2026, 9, 10);
   begin
      if not Real_Data_Available then
         Put_Line ("    [SKIP] Real authority not present (standalone CI mode)");
         return;
      end if;

      Setup_Sandbox;

      --  1. Preflight rejection on unapproved locus
      Res := Publish_Movement
        (Authority_Dir => Sandbox_Dir,
         From_Locus    => "smbc",
         To_Locus      => "bitcoin",
         Amount        => 100,
         Valid_On      => D,
         Description   => "Invalid locus test");
      Assert (not Res.Success, "Publish rejects unapproved TO locus");

      Res := Publish_Movement
        (Authority_Dir => Sandbox_Dir,
         From_Locus    => "crypto",
         To_Locus      => "cash",
         Amount        => 100,
         Valid_On      => D,
         Description   => "Invalid locus test");
      Assert (not Res.Success, "Publish rejects unapproved FROM locus");

      --  2. Preflight rejection on identical loci
      Res := Publish_Movement
        (Authority_Dir => Sandbox_Dir,
         From_Locus    => "smbc",
         To_Locus      => "smbc",
         Amount        => 100,
         Valid_On      => D,
         Description   => "Same locus test");
      Assert (not Res.Success, "Publish rejects identical FROM and TO loci");

      --  3. Preflight rejection on non-positive amount
      Res := Publish_Movement
        (Authority_Dir => Sandbox_Dir,
         From_Locus    => "smbc",
         To_Locus      => "paypay",
         Amount        => 0,
         Valid_On      => D,
         Description   => "Zero amount test");
      Assert (not Res.Success, "Publish rejects zero amount");

      --  4. Valid publication of two-party movement
      Res := Publish_Movement
        (Authority_Dir => Sandbox_Dir,
         From_Locus    => "smbc",
         To_Locus      => "paypay",
         Amount        => 500,
         Valid_On      => D,
         Description   => "Test transfer smbc to paypay");
      Assert (Res.Success, "Valid Movement publication succeeds");
      Assert
        (Res.Event_Id_Str (1 .. Res.Event_Id_Len) = "record-29",
         "Allocated fresh sequential EventId record-29");

      --  5. Verify updated manifest authority
      declare
         Man_Res    : constant Read_Manifest_Result :=
           Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Failed_Fam : Manifest_Family;
      begin
         Assert (Man_Res.Success, "Updated CURRENT manifest loads successfully");
         Assert
           (Verify_All_Objects (Sandbox_Dir, Man_Res.Manifest, Failed_Fam),
            "All 6 authority objects pass cryptographic SHA-256 integrity");
      end;

      --  6. Verify updated event memory contains record-29 with balanced effects
      declare
         Man_Res : constant Read_Manifest_Result :=
           Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Ev_Rel  : constant String :=
           Man_Res.Manifest (Family_Event).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event).Path_Len);
         Ev_Res  : constant Read_Result :=
           Read_Event_Memory_File (Sandbox_Dir & "/" & Ev_Rel);
         Found_29 : Boolean := False;
         Rec_29   : Event;
      begin
         Assert (Ev_Res.Success, "Updated EventMemory file loads successfully");
         Assert (Ev_Res.Events.Length = 589, "Event count increased from 588 to 589");

         for Ev of Ev_Res.Events loop
            if Id (Ev).Token.Length = 9
              and then Id (Ev).Token.Value (1 .. 9) = "record-29"
            then
               Found_29 := True;
               Rec_29   := Ev;
               exit;
            end if;
         end loop;

         Assert (Found_29, "record-29 found in updated EventMemory");
         Assert (Effect_Count (Rec_29) = 2, "record-29 has exactly 2 effects");
         Assert
           (Quantity_At (Rec_29, (Token => Make_Token ("smbc")), (Token => Make_Token ("jpy"))) = -500,
            "smbc effect is -500 JPY");
         Assert
           (Quantity_At (Rec_29, (Token => Make_Token ("paypay")), (Token => Make_Token ("jpy"))) = 500,
            "paypay effect is +500 JPY");
      end;

      --  7. Verify updated validity contains occurrence date for record-29
      declare
         Man_Res    : constant Read_Manifest_Result :=
           Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Val_Rel    : constant String :=
           Man_Res.Manifest (Family_Actual_Validity).Rel_Path
             (1 .. Man_Res.Manifest (Family_Actual_Validity).Path_Len);
         Val_Res    : constant Read_Validity_Result :=
           Read_Validity_File (Sandbox_Dir & "/" & Val_Rel);
         Found_Date : Date_Type;
         Date_Found : Boolean;
      begin
         Assert (Val_Res.Success, "Updated ActualValidity file loads successfully");
         Assert (Entry_Count (Val_Res.Memory) = 589, "Validity count increased from 588 to 589");

         Find_Occurrence_Date
           (Val_Res.Memory, (Token => Make_Token ("record-29")), Found_Date, Date_Found);
         Assert (Date_Found, "record-29 has occurrence date fact");
         Assert (Equal_Date (Found_Date, D), "record-29 occurrence date matches 2026-09-10");
      end;

      --  8. Verify updated descriptions contains text for record-29
      declare
         Man_Res    : constant Read_Manifest_Result :=
           Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Desc_Rel   : constant String :=
           Man_Res.Manifest (Family_Event_Description).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event_Description).Path_Len);
         Desc_Res   : constant Read_Description_Result :=
           Read_Description_File (Sandbox_Dir & "/" & Desc_Rel);
         Found_Desc : Description_Text;
         Desc_Found : Boolean;
      begin
         Assert (Desc_Res.Success, "Updated EventDescription file loads successfully");
         Assert (Entry_Count (Desc_Res.Memory) = 589, "Description count increased from 588 to 589");

         Find_Description
           (Desc_Res.Memory, (Token => Make_Token ("record-29")), Found_Desc, Desc_Found);
         Assert (Desc_Found, "record-29 has description fact");
         Assert
           (To_String (Found_Desc) = "Test transfer smbc to paypay",
            "record-29 description matches published text");
      end;

      --  9. Fail-Closed preflight rejection for Reversal on non-existent event
      Res := Publish_Reversal
        (Authority_Dir   => Sandbox_Dir,
         Target_Event_Id => "record-9999",
         Valid_On        => D,
         Description     => "Revert missing");
      Assert (not Res.Success, "Reversal rejects non-existent target event");

      --  10. Reversal rejects target that is already a reversal
      Res := Publish_Reversal
        (Authority_Dir   => Sandbox_Dir,
         Target_Event_Id => "reversal-of:record-1",
         Valid_On        => D,
         Description     => "Revert a reversal");
      Assert (not Res.Success, "Reversal rejects target with reversal-of prefix");

      --  11. Publish valid Reversal of record-29
      Res := Publish_Reversal
        (Authority_Dir   => Sandbox_Dir,
         Target_Event_Id => "record-29",
         Valid_On        => D,
         Description     => "Reverting test transfer record-29",
         Reversals_Path  => Sandbox_Dir & "/actual-reversals.loam");
      Assert (Res.Success, "Publish_Reversal of record-29 succeeds");
      Assert
        (Res.Event_Id_Str (1 .. Res.Event_Id_Len) = "reversal-of:record-29",
         "Reversal EventId matches reversal-of:record-29");

      --  12. Verify event memory has reversal-of:record-29 with exactly negated effects
      declare
         Man_Res : constant Read_Manifest_Result :=
           Read_Manifest_File (Sandbox_Dir & "/CURRENT");
         Ev_Rel  : constant String :=
           Man_Res.Manifest (Family_Event).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event).Path_Len);
         Ev_Res  : constant Read_Result :=
           Read_Event_Memory_File (Sandbox_Dir & "/" & Ev_Rel);
         Found_Rev : Boolean := False;
         Rev_Ev    : Event;
      begin
         Assert (Ev_Res.Success, "EventMemory reloads after reversal");
         Assert (Ev_Res.Events.Length = 590, "Event count increased to 590");

         for Ev of Ev_Res.Events loop
            if Id (Ev).Token.Length = 21
              and then Id (Ev).Token.Value (1 .. 21) = "reversal-of:record-29"
            then
               Found_Rev := True;
               Rev_Ev    := Ev;
               exit;
            end if;
         end loop;

         Assert (Found_Rev, "reversal-of:record-29 found in EventMemory");
         Assert (Effect_Count (Rev_Ev) = 2, "reversal-of:record-29 has exactly 2 effects");
         Assert
           (Quantity_At (Rev_Ev, (Token => Make_Token ("smbc")), (Token => Make_Token ("jpy"))) = 500,
            "smbc effect is inverted to +500 JPY");
         Assert
           (Quantity_At (Rev_Ev, (Token => Make_Token ("paypay")), (Token => Make_Token ("jpy"))) = -500,
            "paypay effect is inverted to -500 JPY");
      end;

      --  Verify actual-reversals.loam sidecar persistence
      declare
         Rev_Res : constant HRA_N.Storage.Actual_Reversal_Reader.Read_Result :=
           HRA_N.Storage.Actual_Reversal_Reader.Read_Actual_Reversal_File
             (Sandbox_Dir & "/actual-reversals.loam");
      begin
         Assert (Rev_Res.Success, "actual-reversals.loam loads successfully after Publish_Reversal");
         Assert_Equal_Int (1, Long_Long_Integer (Entry_Count (Rev_Res.Memory)), "actual-reversals has 1 entry");
         Assert (Is_Target_Reversed (Rev_Res.Memory, (Token => Make_Token ("record-29"))), "record-29 marked reversed in sidecar");
      end;

      --  13. Fail-Closed prevention of double-reversal
      Res := Publish_Reversal
        (Authority_Dir   => Sandbox_Dir,
         Target_Event_Id => "record-29",
         Valid_On        => D,
         Description     => "Second reversal attempt",
         Reversals_Path  => Sandbox_Dir & "/actual-reversals.loam");
      Assert (not Res.Success, "Double reversal of record-29 is strictly rejected");

      --  14. Overall Doctor health audit on the reversed authority
      declare
         Doc_Report : Doctor_Report;
      begin
         Run_Doctor
           (Authority_Dir => Sandbox_Dir,
            Coverage_Path => Real_Data_Dir & "/zero-origin-coverage.loam",
            Report        => Doc_Report,
            Quiet         => True);
         Assert (Doc_Report.Overall_Healthy, "Doctor audit 100% HEALTHY after movement reversal");
      end;
   end Run;

end Test_Publisher;
