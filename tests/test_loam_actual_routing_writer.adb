with Ada.Directories;
with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Types;          use HRA_N.Core.Types;
with HRA_N.Core.Validity;       use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Actual_Routing_Writer;
use HRA_N.Storage.Loam_Actual_Routing_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Actual_Routing_Writer is

   use type Routing_Publish_Status;

   Root : constant String := "/tmp/hra_n_loam_actual_routing_writer_test";
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
      Admitted_Locus : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL &
        "LOCUS" & HT & "cash" & NL;
      Empty_Locus : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL;

      Draft_Cash_Init : constant Routing_Draft :=
        (Locus          => (Token => Make_Token ("cash")),
         Effective_Kind => Routing_Initial,
         Effective_On   => (Year => 1900, Month => 1, Day => 1),
         Managed        => True,
         Purpose        => Make_Token ("Food"));

      Draft_Cash_Later : constant Routing_Draft :=
        (Locus          => (Token => Make_Token ("cash")),
         Effective_Kind => Routing_From_Date,
         Effective_On   => (Year => 2026, Month => 10, Day => 1),
         Managed        => False,
         Purpose        => (Length => 0, Value => [others => ' ']));
   begin
      Reset_Root;

      --  1. Invalid root directory
      declare
         Res : constant Publish_Result := Publish_Route ("", Draft_Cash_Init);
      begin
         Assert (not Res.Success, "empty root fails");
         Assert (Res.Status = Invalid_Root_Directory, "status is Invalid_Root_Directory");
         Assert (Format_Error (Res)'Length > 0, "Format_Error non-empty");
      end;

      --  2. Invalid locus token
      declare
         Bad_Draft : constant Routing_Draft :=
           (Locus          => (Token => (Length => 0, Value => [others => ' '])),
            Effective_Kind => Routing_Initial,
            Effective_On   => (Year => 1900, Month => 1, Day => 1),
            Managed        => False,
            Purpose        => (Length => 0, Value => [others => ' ']));
         Res : constant Publish_Result := Publish_Route (Root, Bad_Draft);
      begin
         Assert (not Res.Success, "empty locus fails");
         Assert (Res.Status = Invalid_Locus_Token, "status is Invalid_Locus_Token");
      end;

      --  3. Invalid purpose token
      declare
         Bad_Draft : constant Routing_Draft :=
           (Locus          => (Token => Make_Token ("cash")),
            Effective_Kind => Routing_Initial,
            Effective_On   => (Year => 1900, Month => 1, Day => 1),
            Managed        => True,
            Purpose        => (Length => 0, Value => [others => ' ']));
         Res : constant Publish_Result := Publish_Route (Root, Bad_Draft);
      begin
         Assert (not Res.Success, "empty purpose fails");
         Assert (Res.Status = Invalid_Purpose_Token, "status is Invalid_Purpose_Token");
      end;

      --  4. Invalid effective date
      declare
         Bad_Draft : constant Routing_Draft :=
           (Locus          => (Token => Make_Token ("cash")),
            Effective_Kind => Routing_From_Date,
            Effective_On   => (Year => 2026, Month => 2, Day => 29),
            Managed        => False,
            Purpose        => (Length => 0, Value => [others => ' ']));
         Res : constant Publish_Result := Publish_Route (Root, Bad_Draft);
      begin
         Assert (not Res.Success, "invalid date fails");
         Assert (Res.Status = Invalid_Effective_Date, "status is Invalid_Effective_Date");
      end;

      --  5. Locus_Admission_Missing
      declare
         Res : constant Publish_Result := Publish_Route (Root, Draft_Cash_Init);
      begin
         Assert (not Res.Success, "missing locus admission fails");
         Assert (Res.Status = Locus_Admission_Missing, "status is Locus_Admission_Missing");
      end;

      --  6. Locus_Admission_Read_Error
      Write_Fixture ("locus-admission.loam", "CORRUPT_BYTES" & NL);
      declare
         Res : constant Publish_Result := Publish_Route (Root, Draft_Cash_Init);
      begin
         Assert (not Res.Success, "corrupt locus admission fails");
         Assert (Res.Status = Locus_Admission_Read_Error, "status is Locus_Admission_Read_Error");
      end;

      --  7. Locus_Not_Admitted
      Write_Fixture ("locus-admission.loam", Empty_Locus);
      declare
         Res : constant Publish_Result := Publish_Route (Root, Draft_Cash_Init);
      begin
         Assert (not Res.Success, "unadmitted locus fails");
         Assert (Res.Status = Locus_Not_Admitted, "status is Locus_Not_Admitted");
      end;

      --  8. Successful initial publish (creates actual-routing.loam)
      Write_Fixture ("locus-admission.loam", Admitted_Locus);
      declare
         Res : constant Publish_Result := Publish_Route (Root, Draft_Cash_Init);
      begin
         Assert (Res.Success, "initial route publish succeeds");
         Assert (Format_Error (Res) = "", "Format_Error empty on success");
      end;

      --  9. Duplicate coordinate check
      declare
         Res : constant Publish_Result := Publish_Route (Root, Draft_Cash_Init);
      begin
         Assert (not Res.Success, "duplicate coordinate fails");
         Assert (Res.Status = Duplicate_Coordinate, "status is Duplicate_Coordinate");
         Assert (Format_Error (Res)'Length > 0, "Duplicate_Coordinate Format_Error non-empty");
      end;

      --  10. Second publish with Routing_From_Date succeeds
      declare
         Res : constant Publish_Result := Publish_Route (Root, Draft_Cash_Later);
      begin
         Assert (Res.Success, "second route publish succeeds");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Actual_Routing_Writer;
