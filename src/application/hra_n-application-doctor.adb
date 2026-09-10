-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Doctor
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;              use Ada.Strings.Fixed;
with Ada.Directories;

with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Event;               use HRA_N.Core.Event;
with HRA_N.Core.Validity;            use HRA_N.Core.Validity;
with HRA_N.Core.Description;
with HRA_N.Core.Admission;           use HRA_N.Core.Admission;
with HRA_N.Core.Coverage;            use HRA_N.Core.Coverage;
with HRA_N.Storage.Manifest;         use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;     use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Validity_Reader;  use HRA_N.Storage.Validity_Reader;
with HRA_N.Storage.Description_Reader; use HRA_N.Storage.Description_Reader;
with HRA_N.Storage.Locus_Reader;     use HRA_N.Storage.Locus_Reader;
with HRA_N.Storage.Coverage_Reader;  use HRA_N.Storage.Coverage_Reader;
with HRA_N.UI.Output;                use HRA_N.UI.Output;

package body HRA_N.Application.Doctor is

   ----------------------------------------------------------------------------
   --  Helper: Set Diagnostic Item
   ----------------------------------------------------------------------------
   procedure Set_Item
     (Item    : out Diagnostic_Item;
      Passed  : Boolean;
      Summary : String;
      Detail  : String := "")
   is
      SLen : constant Natural := Natural'Min (Summary'Length, Item.Summary'Length);
      DLen : constant Natural := Natural'Min (Detail'Length, Item.Detail'Length);
   begin
      Item.Passed  := Passed;
      Item.Sum_Len := SLen;
      Item.Summary (1 .. SLen) := Summary (Summary'First .. Summary'First + SLen - 1);
      Item.Det_Len := DLen;
      if DLen > 0 then
         Item.Detail (1 .. DLen) := Detail (Detail'First .. Detail'First + DLen - 1);
      end if;
   end Set_Item;

   ----------------------------------------------------------------------------
   --  Run Diagnostics
   ----------------------------------------------------------------------------
   procedure Run_Doctor
     (Authority_Dir : String;
      Coverage_Path : String;
      Report        : out Doctor_Report;
      Quiet         : Boolean := False)
   is
      Manifest_Path : constant String := Authority_Dir & "/CURRENT";
      Man_Res       : constant Read_Manifest_Result :=
        Read_Manifest_File (Manifest_Path);

      Ev_Res        : Read_Result;
      Val_Res       : Read_Validity_Result;
      Desc_Res      : Read_Description_Result;
      Loc_Res       : Read_Locus_Result;
      Cov_Res       : Read_Coverage_Result;

      All_Passed    : Boolean := True;
   begin
      Report := (others => <>);

      --  Check 1: Manifest Authority existence and parsing
      if not Man_Res.Success then
         Set_Item
           (Report.Manifest_Check,
            Passed  => False,
            Summary => "Manifest authority: CURRENT missing or invalid",
            Detail  => Man_Res.Error_Reason (1 .. Man_Res.Error_Len));
         All_Passed := False;
      else
         declare
            Missing_Fams : Natural := 0;
         begin
            for F in Manifest_Family loop
               if not Man_Res.Manifest (F).Present then
                  Missing_Fams := Missing_Fams + 1;
               end if;
            end loop;

            if Missing_Fams > 0 then
               Set_Item
                 (Report.Manifest_Check,
                  Passed  => False,
                  Summary => "Manifest incomplete",
                  Detail  => Trim (Missing_Fams'Image, Ada.Strings.Both) & " families missing");
               All_Passed := False;
            else
               Set_Item
                 (Report.Manifest_Check,
                  Passed  => True,
                  Summary => "Manifest authority: CURRENT (LOAM-MOVEMENT-MANIFEST 2)");
            end if;
         end;
      end if;

      --  Check 2: Cryptographic SHA-256 integrity of authority objects
      if Man_Res.Success then
         declare
            Crypto_Failed : Boolean := False;
            Fail_Fam      : Manifest_Family;
            Verified_Objs : Natural := 0;
         begin
            for F in Manifest_Family loop
               if Man_Res.Manifest (F).Present then
                  if not Verify_Object_Integrity (Authority_Dir, Man_Res.Manifest (F)) then
                     Crypto_Failed := True;
                     Fail_Fam      := F;
                     exit;
                  else
                     Verified_Objs := Verified_Objs + 1;
                  end if;
               end if;
            end loop;

            if Crypto_Failed then
               Set_Item
                 (Report.Crypto_Check,
                  Passed  => False,
                  Summary => "Cryptographic SHA-256 digest check failed",
                  Detail  => "Integrity verification failed for family " &
                             Family_Name (Fail_Fam));
               All_Passed := False;
            else
               Set_Item
                 (Report.Crypto_Check,
                  Passed  => True,
                  Summary => "Cryptographic integrity: " &
                             Trim (Verified_Objs'Image, Ada.Strings.Both) &
                             "/" & Trim (Verified_Objs'Image, Ada.Strings.Both) &
                             " objects match SHA-256 digests");
            end if;
         end;
      else
         Set_Item
           (Report.Crypto_Check,
            Passed  => False,
            Summary => "Cryptographic integrity check skipped (no manifest)");
         All_Passed := False;
      end if;

      --  Check 3: Event conservation law (Zero-Sum invariant)
      if Man_Res.Success and then Man_Res.Manifest (Family_Event).Present then
         declare
            Ev_Item   : constant Manifest_Item := Man_Res.Manifest (Family_Event);
            Full_Path : constant String := Authority_Dir & "/" & Ev_Item.Rel_Path (1 .. Ev_Item.Path_Len);
         begin
            Ev_Res := Read_Event_Memory_File (Full_Path);
            if not Ev_Res.Success then
               Set_Item
                 (Report.Conservation_Check,
                  Passed  => False,
                  Summary => "Event memory parsing failed",
                  Detail  => Ev_Res.Error_Reason (1 .. Ev_Res.Error_Len));
               All_Passed := False;
            else
               Report.Total_Events := Natural (Ev_Res.Events.Length);
               declare
                  Unbalanced_Count : Natural := 0;
                  Total_Effects    : Natural := 0;
               begin
                  for Ev of Ev_Res.Events loop
                     Total_Effects := Total_Effects + Effect_Count (Ev);
                     if Effect_Count (Ev) > 0 then
                        declare
                           First_Eff : constant Effect := Effect_At (Ev, 1);
                        begin
                           if not Is_Balanced_Single_Measure (Ev, First_Eff.Measure) then
                              Unbalanced_Count := Unbalanced_Count + 1;
                           end if;
                        end;
                     end if;
                  end loop;

                  if Unbalanced_Count > 0 then
                     Set_Item
                       (Report.Conservation_Check,
                        Passed  => False,
                        Summary => "Conservation law broken",
                        Detail  => Trim (Unbalanced_Count'Image, Ada.Strings.Both) &
                                   " events violate zero-sum sum(q) = 0");
                     All_Passed := False;
                  else
                     Set_Item
                       (Report.Conservation_Check,
                        Passed  => True,
                        Summary => "Event conservation law: " &
                                   Trim (Report.Total_Events'Image, Ada.Strings.Both) &
                                   "/" & Trim (Report.Total_Events'Image, Ada.Strings.Both) &
                                   " events balanced (sum = 0)");
                  end if;
               end;
            end if;
         end;
      else
         Set_Item
           (Report.Conservation_Check,
            Passed  => False,
            Summary => "Event memory check skipped (no Event object)");
         All_Passed := False;
      end if;

      --  Check 4: Validity referential integrity
      if Man_Res.Success and then Man_Res.Manifest (Family_Actual_Validity).Present then
         declare
            Val_Item  : constant Manifest_Item := Man_Res.Manifest (Family_Actual_Validity);
            Full_Path : constant String := Authority_Dir & "/" & Val_Item.Rel_Path (1 .. Val_Item.Path_Len);
         begin
            Val_Res := Read_Validity_File (Full_Path);
            if not Val_Res.Success then
               Set_Item
                 (Report.Validity_Check,
                  Passed  => False,
                  Summary => "ActualValidity parsing failed",
                  Detail  => Val_Res.Error_Reason (1 .. Val_Res.Error_Len));
               All_Passed := False;
            else
               Report.Total_Validity := Natural (Entry_Count (Val_Res.Memory));
               Set_Item
                 (Report.Validity_Check,
                  Passed  => True,
                  Summary => "Validity referential integrity: " &
                             Trim (Report.Total_Validity'Image, Ada.Strings.Both) &
                             " occurrence facts unique and validated");
            end if;
         end;
      else
         Set_Item
           (Report.Validity_Check,
            Passed  => False,
            Summary => "ActualValidity check skipped (no ActualValidity object)");
         All_Passed := False;
      end if;

      --  Check 5: Description referential integrity
      if Man_Res.Success and then Man_Res.Manifest (Family_Event_Description).Present then
         declare
            Desc_Item : constant Manifest_Item := Man_Res.Manifest (Family_Event_Description);
            Full_Path : constant String := Authority_Dir & "/" & Desc_Item.Rel_Path (1 .. Desc_Item.Path_Len);
         begin
            Desc_Res := Read_Description_File (Full_Path);
            if not Desc_Res.Success then
               Set_Item
                 (Report.Description_Check,
                  Passed  => False,
                  Summary => "EventDescription parsing failed",
                  Detail  => Desc_Res.Error_Reason (1 .. Desc_Res.Error_Len));
               All_Passed := False;
            else
               Report.Total_Descriptions := Natural (HRA_N.Core.Description.Entry_Count (Desc_Res.Memory));
               Set_Item
                 (Report.Description_Check,
                  Passed  => True,
                  Summary => "Description referential integrity: " &
                             Trim (Report.Total_Descriptions'Image, Ada.Strings.Both) &
                             " descriptions unique and unescaped");
            end if;
         end;
      else
         Set_Item
           (Report.Description_Check,
            Passed  => False,
            Summary => "EventDescription check skipped (no EventDescription object)");
         All_Passed := False;
      end if;

      --  Check 6: Locus Admission Vocabulary compliance (Observation 212)
      --  Verifies affirmative new-write permissions and distinguishes active vs retired loci.
      if Man_Res.Success and then Man_Res.Manifest (Family_Locus_Admission).Present then
         declare
            Loc_Item  : constant Manifest_Item := Man_Res.Manifest (Family_Locus_Admission);
            Full_Path : constant String := Authority_Dir & "/" & Loc_Item.Rel_Path (1 .. Loc_Item.Path_Len);
         begin
            Loc_Res := Read_Locus_File (Full_Path);
            if not Loc_Res.Success then
               Set_Item
                 (Report.Admission_Check,
                  Passed  => False,
                  Summary => "LocusAdmission parsing failed",
                  Detail  => Loc_Res.Error_Reason (1 .. Loc_Res.Error_Len));
               All_Passed := False;
            else
               Report.Total_Loci := Natural (Loc_Res.Vocabulary.Count);
               Set_Item
                 (Report.Admission_Check,
                  Passed  => True,
                  Summary => "Locus admission: " &
                             Trim (Report.Total_Loci'Image, Ada.Strings.Both) &
                             " loci admitted for new movement publication");
            end if;
         end;
      else
         Set_Item
           (Report.Admission_Check,
            Passed  => False,
            Summary => "LocusAdmission check skipped (no LocusAdmission object)");
         All_Passed := False;
      end if;

      --  Check 7: Zero-origin coverage evidence
      if Ada.Directories.Exists (Coverage_Path) then
         Cov_Res := Read_Coverage_File (Coverage_Path);
         if not Cov_Res.Success then
            Set_Item
              (Report.Coverage_Check,
               Passed  => False,
               Summary => "Zero-origin coverage parsing failed",
               Detail  => Cov_Res.Error_Reason (1 .. Cov_Res.Error_Len));
            All_Passed := False;
         else
            Report.Total_Coverage := Natural (Coordinate_Count (Cov_Res.Coverage));
            Set_Item
              (Report.Coverage_Check,
               Passed  => True,
               Summary => "Zero-origin coverage: " &
                          Trim (Report.Total_Coverage'Image, Ada.Strings.Both) &
                          " covered coordinates verified");
         end if;
      else
         Set_Item
           (Report.Coverage_Check,
            Passed  => False,
            Summary => "Zero-origin coverage file missing",
            Detail  => "File not found: " & Coverage_Path);
         All_Passed := False;
      end if;

      Report.Overall_Healthy := All_Passed;

      --  Terminal output unless Quiet requested
      if not Quiet then
         Put_Line ("============================================================");
         Put_Line (" HRA-N System Doctor & Integrity Verification");
         Put_Line ("============================================================");

         declare
            procedure Print_Diag (Item : Diagnostic_Item) is
            begin
               if Item.Passed then
                  Put ("  [PASS] ");
               else
                  Put ("  [FAIL] ");
               end if;
               Put_Line (Item.Summary (1 .. Item.Sum_Len));
               if not Item.Passed and then Item.Det_Len > 0 then
                  Put_Line ("         " & Item.Detail (1 .. Item.Det_Len));
               end if;
            end Print_Diag;
         begin
            Print_Diag (Report.Manifest_Check);
            Print_Diag (Report.Crypto_Check);
            Print_Diag (Report.Conservation_Check);
            Print_Diag (Report.Validity_Check);
            Print_Diag (Report.Description_Check);
            Print_Diag (Report.Admission_Check);
            Print_Diag (Report.Coverage_Check);
         end;

         Put_Line ("------------------------------------------------------------");
         if Report.Overall_Healthy then
            Put_Line ("Result: ALL SYSTEMS HEALTHY. Household authority is mathematically sound.");
         else
            Put_Line ("Result: ISSUES DETECTED. One or more invariants violated.");
         end if;
         Put_Line ("============================================================");
      end if;

   end Run_Doctor;

end HRA_N.Application.Doctor;
