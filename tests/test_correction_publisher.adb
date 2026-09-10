-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Correction_Publisher
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Streams; with Ada.Streams.Stream_IO;
with GNAT.OS_Lib;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Correction;
with HRA_N.Application.Correction_Frontier; use HRA_N.Application.Correction_Frontier;
with HRA_N.Application.Correction_Publisher; use HRA_N.Application.Correction_Publisher;
with Test_Support; use Test_Support;

package body Test_Correction_Publisher is

   Sandbox_Dir   : constant String := "/tmp/hra_n_test_corr_pub";
   Authority_Dir : constant String := Sandbox_Dir & "/movement-authority";
   Corr_File     : constant String := Sandbox_Dir & "/actual-corrections.loam";
   Rev_File      : constant String := Sandbox_Dir & "/actual-reversals.loam";

   function Source_Auth_Dir return String is
     (Real_Data_Dir & "/movement-authority");

   procedure Setup_Sandbox is
      Success : Boolean;
      Args    : GNAT.OS_Lib.Argument_List (1 .. 3);
      Err     : String (1 .. 128);
      Err_Len : Natural;
      Ok      : Boolean;
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

      Ada.Directories.Create_Path (Authority_Dir);

      Args (1) := new String'("-R");
      Args (2) := new String'(Source_Auth_Dir & "/");
      Args (3) := new String'(Authority_Dir & "/");
      GNAT.OS_Lib.Spawn
        (Program_Name => "/bin/cp",
         Args         => Args (1 .. 3),
         Success      => Success);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      GNAT.OS_Lib.Free (Args (3));

      --  Initialize empty actual-reversals.loam
      Ok := Write_File_Atomically
        (Rev_File,
         "LOAM-ACTUAL-REVERSAL-MEMORY" & ASCII.HT & "1" & ASCII.LF,
         Err, Err_Len);
      Assert (Ok, "Create empty actual-reversals.loam");
   end Setup_Sandbox;

   function Read_File_String (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
      use type SIO.Count;
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         if Size = 0 then
            SIO.Close (File);
            return "";
         end if;
         SIO.Read (File, Data, Last);
         SIO.Close (File);
         declare
            Res : String (1 .. Natural (Last));
            for Res'Address use Data'Address;
         begin
            return Res;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return "";
   end Read_File_String;

   procedure Run is
   begin
      if not Real_Data_Available then
         return;
      end if;

      --  Test 1: Normal Correction Publication
      Setup_Sandbox;
      declare
         Draft : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-1",
              From_Locus  => "cash",
              To_Locus    => "yucho",
              Amount      => 2000,
              Description => "Food expenditure corrected to yucho");
         Receipt : constant Correction_Receipt :=
           Publish_Correction
             (Authority_Dir   => Authority_Dir,
              Correction_Path => Corr_File,
              Reversals_Path  => Rev_File,
              Draft           => Draft);
      begin
         Assert (Receipt.Success, "Correction publication succeeds for record-1");
         Assert (Receipt.Target.Token.Value (1 .. Receipt.Target.Token.Length) = "record-1",
                 "Receipt target matches record-1");
         Assert (Receipt.Replacement.Token.Value (1 .. Receipt.Replacement.Token.Length) = "replacement-1",
                 "Receipt replacement allocated replacement-1");
         Assert (Receipt.Correction.Token.Value (1 .. Receipt.Correction.Token.Length) = "correction-1",
                 "Receipt correction allocated correction-1");
         Assert (Receipt.Carried_Date, "Receipt indicates occurrence date carried");
         Assert (Receipt.Published_Description, "Receipt indicates description published");
         Assert (not Receipt.Resumed, "Initial publication is not resumed");

         Assert (Ada.Directories.Exists (Corr_File), "actual-corrections.loam created");
         declare
            Corr_Content : constant String := Read_File_String (Corr_File);
         begin
            Assert (Corr_Content'Length > 0, "Correction sidecar non-empty");
         end;

         --  Verify CURRENT manifest points to objects containing replacement-1
         declare
            Man_Res : constant Read_Manifest_Result :=
              Read_Manifest_File (Authority_Dir & "/CURRENT");
            Ev_Path : constant String := Authority_Dir & "/" &
              Man_Res.Manifest (Family_Event).Rel_Path
                (1 .. Man_Res.Manifest (Family_Event).Path_Len);
            Val_Path : constant String := Authority_Dir & "/" &
              Man_Res.Manifest (Family_Actual_Validity).Rel_Path
                (1 .. Man_Res.Manifest (Family_Actual_Validity).Path_Len);
            Desc_Path : constant String := Authority_Dir & "/" &
              Man_Res.Manifest (Family_Event_Description).Rel_Path
                (1 .. Man_Res.Manifest (Family_Event_Description).Path_Len);
            Ev_Text : constant String := Read_File_String (Ev_Path);
            Val_Text : constant String := Read_File_String (Val_Path);
            Desc_Text : constant String := Read_File_String (Desc_Path);

            Ev_Read : constant Read_Result := Read_Event_Memory_File (Ev_Path);
            Corr_Read : constant HRA_N.Storage.Correction.Read_Result :=
              HRA_N.Storage.Correction.Read_File (Corr_File);
            Front_Res : Resolution_Result;
         begin
            Assert (Ev_Text'Length > 0, "Event object non-empty");
            Assert (Val_Text'Length > 0, "Validity object non-empty");
            Assert (Desc_Text'Length > 0, "Description object non-empty");

            Resolve (Ev_Read.Events, Corr_Read.Memory, Draft.Target, Front_Res);
            Assert (Front_Res.State = Resolution_Current, "Frontier resolves record-1 as current");
            Assert (Front_Res.Effective.Token.Value (1 .. Front_Res.Effective.Token.Length) =
                    "replacement-1",
                    "Frontier resolves record-1 to replacement-1");
            Assert (Front_Res.Depth = 1, "Frontier depth is 1");
         end;

         --  Test 2: Chained Correction and Superseded Target Rejection
         declare
            Draft2 : constant Correction_Draft :=
              Make_Two_Party_Draft
                (Target      => "replacement-1",
                 From_Locus  => "cash",
                 To_Locus    => "yucho",
                 Amount      => 2500,
                 Description => "Chained correction adjusting amount");
            Receipt2 : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft2);
         begin
            Assert (Receipt2.Success, "Chained correction publication succeeds for replacement-1");
            Assert (Receipt2.Target.Token.Value (1 .. Receipt2.Target.Token.Length) = "replacement-1",
                    "Chained target matches replacement-1");
            Assert (Receipt2.Replacement.Token.Value (1 .. Receipt2.Replacement.Token.Length) = "replacement-2",
                    "Chained replacement allocated replacement-2");
            Assert (Receipt2.Correction.Token.Value (1 .. Receipt2.Correction.Token.Length) = "correction-2",
                    "Chained correction allocated correction-2");

            --  Frontier resolution from root record-1 resolves to replacement-2 with depth 2
            declare
               Man_Res : constant Read_Manifest_Result :=
                 Read_Manifest_File (Authority_Dir & "/CURRENT");
               Ev_Path : constant String := Authority_Dir & "/" &
                 Man_Res.Manifest (Family_Event).Rel_Path
                   (1 .. Man_Res.Manifest (Family_Event).Path_Len);
               Ev_Read : constant Read_Result := Read_Event_Memory_File (Ev_Path);
               Corr_Read : constant HRA_N.Storage.Correction.Read_Result :=
                 HRA_N.Storage.Correction.Read_File (Corr_File);
               Front_Res : Resolution_Result;
            begin
               Resolve (Ev_Read.Events, Corr_Read.Memory, Draft.Target, Front_Res);
               Assert (Front_Res.State = Resolution_Current, "Chain resolves to current");
               Assert (Front_Res.Effective.Token.Value (1 .. Front_Res.Effective.Token.Length) =
                       "replacement-2",
                       "Chain resolves record-1 to replacement-2");
               Assert (Front_Res.Depth = 2, "Chain depth is 2");
            end;

            --  Attempt to correct record-1 again (superseded target fails closed)
            declare
               Draft_Old : constant Correction_Draft :=
                 Make_Two_Party_Draft
                   (Target      => "record-1",
                    From_Locus  => "cash",
                    To_Locus    => "yucho",
                    Amount      => 500);
               Receipt_Old : constant Correction_Receipt :=
                 Publish_Correction
                   (Authority_Dir   => Authority_Dir,
                    Correction_Path => Corr_File,
                    Reversals_Path  => Rev_File,
                    Draft           => Draft_Old);
            begin
               Assert (not Receipt_Old.Success,
                       "Correcting superseded target fails closed");
            end;
         end;
      end;

      --  Test 3: Sidecar-first Interruption and Same-Identity Resume (Required Fault Test 10)
      Setup_Sandbox;
      declare
         Draft : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-2",
              From_Locus  => "cash",
              To_Locus    => "food",
              Amount      => 1500,
              Description => "Interrupted correction test");

         --  Fault: Interrupted after writing correction sidecar
         Receipt_Fault : constant Correction_Receipt :=
           Publish_Correction
             (Authority_Dir   => Authority_Dir,
              Correction_Path => Corr_File,
              Reversals_Path  => Rev_File,
              Draft           => Draft,
              Fault           => Correction_Fault_Interrupt_After_Sidecar);

         Man_Res : constant Read_Manifest_Result :=
           Read_Manifest_File (Authority_Dir & "/CURRENT");
         Ev_Path : constant String := Authority_Dir & "/" &
           Man_Res.Manifest (Family_Event).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event).Path_Len);
         Ev_Read : constant Read_Result := Read_Event_Memory_File (Ev_Path);
         Corr_Read : constant HRA_N.Storage.Correction.Read_Result :=
           HRA_N.Storage.Correction.Read_File (Corr_File);
         Front_Res : Resolution_Result;
      begin
         Assert (not Receipt_Fault.Success, "Fault run returns not Success");
         Assert (Receipt_Fault.Replacement.Token.Value (1 .. Receipt_Fault.Replacement.Token.Length) =
                 "replacement-1",
                 "Allocated replacement-1 before crash");
         Assert (Receipt_Fault.Correction.Token.Value (1 .. Receipt_Fault.Correction.Token.Length) =
                 "correction-1",
                 "Allocated correction-1 before crash");

         --  Sidecar file exists and has the pending correction
         Assert (Corr_Read.Success and then Corr_Read.Memory.Count = 1,
                 "Sidecar retained pending correction on disk");

         --  CURRENT has NOT been updated with replacement-1
         Resolve (Ev_Read.Events, Corr_Read.Memory, Draft.Target, Front_Res);
         Assert (Front_Res.State = Resolution_Unresolved,
                 "Sidecar crash residue projects Resolution_Unresolved");

         --  Retry with the exact same draft
         declare
            Receipt_Retry : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft);
         begin
            Assert (Receipt_Retry.Success, "Retry publication succeeds");
            Assert (Receipt_Retry.Resumed, "Receipt marks operation as resumed");
            Assert (Receipt_Retry.Replacement.Token.Value (1 .. Receipt_Retry.Replacement.Token.Length) =
                    Receipt_Fault.Replacement.Token.Value (1 .. Receipt_Fault.Replacement.Token.Length),
                    "Retry reuses exact replacement-1 identity");
            Assert (Receipt_Retry.Correction.Token.Value (1 .. Receipt_Retry.Correction.Token.Length) =
                    Receipt_Fault.Correction.Token.Value (1 .. Receipt_Fault.Correction.Token.Length),
                    "Retry reuses exact correction-1 identity");

            --  Frontier now resolves cleanly to replacement-1
            declare
               Post_Man : constant Read_Manifest_Result :=
                 Read_Manifest_File (Authority_Dir & "/CURRENT");
               Post_Ev_Path : constant String := Authority_Dir & "/" &
                 Post_Man.Manifest (Family_Event).Rel_Path
                   (1 .. Post_Man.Manifest (Family_Event).Path_Len);
               Post_Ev : constant Read_Result := Read_Event_Memory_File (Post_Ev_Path);
               Post_Corr : constant HRA_N.Storage.Correction.Read_Result :=
                 HRA_N.Storage.Correction.Read_File (Corr_File);
               Post_Front : Resolution_Result;
            begin
               Resolve (Post_Ev.Events, Post_Corr.Memory, Draft.Target, Post_Front);
               Assert (Post_Front.State = Resolution_Current,
                       "Post-retry frontier resolves record-2 as current");
               Assert (Post_Front.Effective.Token.Value (1 .. Post_Front.Effective.Token.Length) =
                       "replacement-1",
                       "Post-retry frontier effective is replacement-1");
            end;
         end;
      end;

      --  Test 4: Sibling Correction Residue Rejection (Required Fault Test 11)
      Setup_Sandbox;
      declare
         Err     : String (1 .. 128);
         Err_Len : Natural;
         Ok      : Boolean;
         Sib_Payload : constant String :=
           "LOAM-EVENT-CORRECTION-MEMORY" & ASCII.HT & "1" & ASCII.LF &
           "CORRECTION" & ASCII.HT & "c-sib-1" & ASCII.HT & "record-3" & ASCII.HT & "replacement-A" & ASCII.LF &
           "CORRECTION" & ASCII.HT & "c-sib-2" & ASCII.HT & "record-3" & ASCII.HT & "replacement-B" & ASCII.LF;
         Draft : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-3",
              From_Locus  => "cash",
              To_Locus    => "food",
              Amount      => 1000);
      begin
         Ok := Write_File_Atomically (Corr_File, Sib_Payload, Err, Err_Len);
         Assert (Ok, "Write sibling correction residue into sidecar");

         declare
            Receipt : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft);
         begin
            Assert (not Receipt.Success, "Sibling correction residue rejects publication fail-closed");
         end;
      end;

      --  Test 5: Relation-Involved Target Rejection (Required Fault Test 12)
      Setup_Sandbox;
      declare
         --  Publish a relation unit targeting record-1
         Man_Res : constant Read_Manifest_Result :=
           Read_Manifest_File (Authority_Dir & "/CURRENT");
         Unit_Path : constant String := Authority_Dir & "/" &
           Man_Res.Manifest (Family_Relation_Unit).Rel_Path
             (1 .. Man_Res.Manifest (Family_Relation_Unit).Path_Len);
         Unit_Content : constant String :=
           "LOAM-RELATION-UNIT" & ASCII.HT & "1" & ASCII.LF &
           "UNIT" & ASCII.HT & "rel-test" & ASCII.HT & "record-1" & ASCII.HT & "effect-1" &
           ASCII.HT & "H" & ASCII.HT & "ext" & ASCII.HT & "500" & ASCII.LF;
         Err : String (1 .. 128);
         Err_Len : Natural;
         Ok : Boolean;
         Draft : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-1",
              From_Locus  => "cash",
              To_Locus    => "food",
              Amount      => 2000);
      begin
         Ok := Write_File_Atomically (Unit_Path, Unit_Content, Err, Err_Len);
         Assert (Ok, "Inject relation unit referencing record-1");

         declare
            Receipt : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft);
         begin
            Assert (not Receipt.Success, "Relation-involved target fails closed");
         end;
      end;

      --  Test 6: Reversal-Involved Target Rejection (Required Fault Test 12)
      Setup_Sandbox;
      declare
         Err     : String (1 .. 128);
         Err_Len : Natural;
         Ok      : Boolean;
         Rev_Content : constant String :=
           "LOAM-ACTUAL-REVERSAL-MEMORY" & ASCII.HT & "1" & ASCII.LF &
           "REVERSE" & ASCII.HT & "record-1" & ASCII.HT & "reversal-1" & ASCII.LF;
         Draft : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-1",
              From_Locus  => "cash",
              To_Locus    => "food",
              Amount      => 2000);
      begin
         Ok := Write_File_Atomically (Rev_File, Rev_Content, Err, Err_Len);
         Assert (Ok, "Inject reversal referencing record-1");

         declare
            Receipt : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft);
         begin
            Assert (not Receipt.Success, "Reversal-involved target fails closed");
         end;
      end;

      --  Test 7: Missing or Malformed Reversal Authority Rejection (Required Fault Test 14)
      Setup_Sandbox;
      declare
         Draft : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-1",
              From_Locus  => "cash",
              To_Locus    => "food",
              Amount      => 2000);
      begin
         --  A: Missing reversals file
         declare
            Receipt : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Sandbox_Dir & "/nonexistent-reversals.loam",
                 Draft           => Draft);
         begin
            Assert (not Receipt.Success, "Missing reversal authority fails closed");
         end;

         --  B: Malformed reversals file
         declare
            Err : String (1 .. 128);
            Err_Len : Natural;
            Ok : Boolean;
         begin
            Ok := Write_File_Atomically (Rev_File, "CORRUPTED_HEADER" & ASCII.LF, Err, Err_Len);
            Assert (Ok, "Write malformed reversals file");
            declare
               Receipt : constant Correction_Receipt :=
                 Publish_Correction
                   (Authority_Dir   => Authority_Dir,
                    Correction_Path => Corr_File,
                    Reversals_Path  => Rev_File,
                    Draft           => Draft);
            begin
               Assert (not Receipt.Success, "Malformed reversal authority fails closed");
            end;
         end;
      end;

      --  Test 8: Malformed Correction Sidecar Rejection (Required Fault Test 14)
      Setup_Sandbox;
      declare
         Err     : String (1 .. 128);
         Err_Len : Natural;
         Ok      : Boolean;
         Draft   : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-1",
              From_Locus  => "cash",
              To_Locus    => "food",
              Amount      => 2000);
      begin
         Ok := Write_File_Atomically (Corr_File, "MALFORMED_HEADER" & ASCII.LF, Err, Err_Len);
         Assert (Ok, "Write malformed correction file");

         declare
            Receipt : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft);
         begin
            Assert (not Receipt.Success, "Malformed correction sidecar fails closed");
         end;
      end;

      --  Test 9: Date Inheritance and Optional Description (Required Fault Test 13)
      Setup_Sandbox;
      declare
         --  Without description
         Draft_No_Desc : constant Correction_Draft :=
           Make_Two_Party_Draft
             (Target      => "record-1",
              From_Locus  => "cash",
              To_Locus    => "food",
              Amount      => 2000);
         Receipt_No_Desc : constant Correction_Receipt :=
           Publish_Correction
             (Authority_Dir   => Authority_Dir,
              Correction_Path => Corr_File,
              Reversals_Path  => Rev_File,
              Draft           => Draft_No_Desc);
      begin
         Assert (Receipt_No_Desc.Success, "Publication without description succeeds");
         Assert (Receipt_No_Desc.Carried_Date, "Carried_Date is True");
         Assert (not Receipt_No_Desc.Published_Description, "Published_Description is False");
      end;

      --  Test 10: Unbalanced or Unadmitted Draft Rejection
      Setup_Sandbox;
      declare
         --  Unbalanced draft
         Draft_Unbal : Correction_Draft;
         Eff1 : constant Effect :=
           (Key     => (Token => Make_Token ("effect-1")),
            Locus   => (Token => Make_Token ("cash")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => 1000));
         Eff2 : constant Effect :=
           (Key     => (Token => Make_Token ("effect-2")),
            Locus   => (Token => Make_Token ("food")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => -500));
      begin
         Draft_Unbal.Target := (Token => Make_Token ("record-1"));
         Draft_Unbal.Effects.Count := 2;
         Draft_Unbal.Effects.Values (1) := Eff1;
         Draft_Unbal.Effects.Values (2) := Eff2;

         declare
            Receipt : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft_Unbal);
         begin
            Assert (not Receipt.Success, "Unbalanced correction draft fails closed");
         end;

         --  Unapproved locus
         declare
            Draft_Unapproved : constant Correction_Draft :=
              Make_Two_Party_Draft
                (Target      => "record-1",
                 From_Locus  => "cash",
                 To_Locus    => "unknown_unapproved_locus_xyz",
                 Amount      => 1000);
            Receipt : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft_Unapproved);
         begin
            Assert (not Receipt.Success, "Unapproved locus in correction draft fails closed");
         end;
      end;

   end Run;

end Test_Correction_Publisher;
