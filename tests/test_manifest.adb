-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Manifest
-------------------------------------------------------------------------------

with Ada.Text_IO;           use Ada.Text_IO;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with Test_Support;           use Test_Support;

package body Test_Manifest is

   procedure Run is
      Auth_Dir      : constant String := Real_Data_Dir & "/movement-authority";
      Manifest_Path : constant String := Auth_Dir & "/CURRENT";

      Fam_Ev     : Manifest_Family;
      Fam_Val    : Manifest_Family;
      Fam_Bad    : Manifest_Family;
      Ok         : Boolean;
      Res_Non    : constant Read_Manifest_Result := Read_Manifest_File ("/non/existent/CURRENT");
      Failed_Fam : Manifest_Family;
   begin
      -- Test 1: Family parse and name round-trip
      Ok := Parse_Family ("Event", Fam_Ev);
      Assert (Ok and then Fam_Ev = Family_Event, "Parse 'Event' to Family_Event");

      Ok := Parse_Family ("ActualValidity", Fam_Val);
      Assert (Ok and then Fam_Val = Family_Actual_Validity, "Parse 'ActualValidity'");

      Ok := Parse_Family ("InvalidFamily", Fam_Bad);
      Assert ((not Ok) and then Fam_Bad = Family_Event, "Reject unknown family name");

      Assert (Family_Name (Family_Event) = "Event", "Family_Name(Family_Event) = 'Event'");

      -- Test 2: Non-existent manifest fails closed
      Assert (not Res_Non.Success, "Non-existent manifest fails closed");

      if not Real_Data_Available then
         Put_Line ("    [SKIP] Real authority manifest not present (standalone CI mode)");
         return;
      end if;

      declare
         Res_Real : constant Read_Manifest_Result := Read_Manifest_File (Manifest_Path);
      begin
         -- Test 3: Real manifest loading
         Assert (Res_Real.Success, "Real CURRENT manifest loads successfully");
      Assert (Res_Real.Manifest (Family_Event).Present, "Manifest contains Event object");
      Assert (Res_Real.Manifest (Family_Actual_Validity).Present, "Manifest contains ActualValidity object");
      Assert (Res_Real.Manifest (Family_Event_Description).Present, "Manifest contains EventDescription object");
      Assert (Res_Real.Manifest (Family_Relation_Unit).Present, "Manifest contains RelationUnit object");
      Assert (Res_Real.Manifest (Family_Relation_Discharge).Present, "Manifest contains RelationDischarge object");
      Assert (Res_Real.Manifest (Family_Locus_Admission).Present, "Manifest contains LocusAdmission object");

      -- Test 4: Verify SHA-256 cryptographic integrity for all declared objects
      declare
         All_Valid : constant Boolean :=
           Verify_All_Objects (Auth_Dir, Res_Real.Manifest, Failed_Fam);
      begin
         Assert (All_Valid, "Cryptographic SHA-256 hash verified for all 6 operational authority objects");
         if not All_Valid then
            Assert (False, "Failed family: " & Family_Name (Failed_Fam));
         end if;
      end;

      -- Test 5: Tamper detection (deliberate wrong hash rejected)
      declare
         Tampered_Item : Manifest_Item := Res_Real.Manifest (Family_Event);
      begin
         Tampered_Item.Digest (1) := '0';  -- Tamper with first hex character
         if Tampered_Item.Digest = Res_Real.Manifest (Family_Event).Digest then
            Tampered_Item.Digest (1) := '1';
         end if;

         Assert (not Verify_Object_Integrity (Auth_Dir, Tampered_Item),
                 "Tampered SHA-256 hash correctly rejected (tamper detection verified)");
      end;
      end;
   end Run;

end Test_Manifest;
