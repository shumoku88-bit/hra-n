-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Actual Validity Publisher & Frontier Qualification
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;             use Ada.Text_IO;
with GNAT.OS_Lib;
with Test_Support;            use Test_Support;
with HRA_N.Core.Types;        use HRA_N.Core.Types;
with HRA_N.Core.Validity;     use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Validity_Frontier;  use HRA_N.Application.Actual_Validity_Frontier;
with HRA_N.Application.Actual_Validity_Publisher; use HRA_N.Application.Actual_Validity_Publisher;
with HRA_N.Application.Correction_Publisher;      use HRA_N.Application.Correction_Publisher;
with HRA_N.Storage.Manifest;  use HRA_N.Storage.Manifest;
with HRA_N.Storage.Validity_Reader; use HRA_N.Storage.Validity_Reader;

package body Test_Actual_Validity_Publisher is

   Sandbox_Dir   : constant String := "/tmp/hra_n_test_validity_pub";
   Authority_Dir : constant String := Sandbox_Dir & "/movement-authority";
   Corr_File     : constant String := Sandbox_Dir & "/actual-corrections.loam";
   Rev_File      : constant String := Sandbox_Dir & "/actual-reversals.loam";

   function Source_Auth_Dir return String is
     (Real_Data_Dir & "/movement-authority");

   procedure Setup_Sandbox is
      Success : Boolean;
      Args    : GNAT.OS_Lib.Argument_List (1 .. 3);
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
      declare
         F : File_Type;
      begin
         Create (F, Out_File, Rev_File);
         Put_Line (F, "LOAM-ACTUAL-REVERSAL-MEMORY" & ASCII.HT & "1");
         Close (F);
      end;
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
         return "";
   end Read_File_String;

   ----------------------------------------------------------------------------
   --  Test Suite 1: Pure Frontier Mechanics
   ----------------------------------------------------------------------------
   procedure Test_Frontier_Mechanics is
      Ev1 : constant Event_Id := (Token => Make_Token ("record-1"));
      Ev2 : constant Event_Id := (Token => Make_Token ("record-2"));

      D1 : constant Date_Type := Make_Date (2026, 9, 3);
      D2 : constant Date_Type := Make_Date (2026, 9, 2);
      D3 : constant Date_Type := Make_Date (2026, 9, 1);
      D4 : constant Date_Type := Make_Date (2026, 8, 31);

      H : Validity_History;
      Mem : Validity_Memory;
      Ok : Boolean;
      Found : Boolean;
      Found_D : Date_Type;
   begin
      --  1. Single fact
      H.Fact_Count := 1;
      H.Facts (1) := (Id => (Token => Make_Token ("validity-1")), Event_Id => Ev1, Valid_On => D1);
      Assert (Frontier_Admissible (H), "Single fact is admissible");
      Ok := Project_Memory (H, Mem);
      Assert (Ok, "Single fact projects to memory");
      Find_Occurrence_Date (Mem, Ev1, Found_D, Found);
      Assert (Found and then Equal_Date (Found_D, D1), "Single fact resolves correct date");

      --  2. Single correction: validity-1 -> validity-2
      H.Fact_Count := 2;
      H.Facts (2) := (Id => (Token => Make_Token ("validity-2")), Event_Id => Ev1, Valid_On => D2);
      H.Correction_Count := 1;
      H.Corrections (1) :=
        (Id          => (Token => Make_Token ("validity-correction-1")),
         Target      => (Token => Make_Token ("validity-1")),
         Replacement => (Token => Make_Token ("validity-2")));
      Assert (Frontier_Admissible (H), "Single correction is admissible");
      Ok := Project_Memory (H, Mem);
      Assert (Ok, "Single correction projects to memory");
      Find_Occurrence_Date (Mem, Ev1, Found_D, Found);
      Assert (Found and then Equal_Date (Found_D, D2), "Correction selects replacement date");

      --  3. Chained correction: validity-1 -> validity-2 -> validity-3
      H.Fact_Count := 3;
      H.Facts (3) := (Id => (Token => Make_Token ("validity-3")), Event_Id => Ev1, Valid_On => D3);
      H.Correction_Count := 2;
      H.Corrections (2) :=
        (Id          => (Token => Make_Token ("validity-correction-2")),
         Target      => (Token => Make_Token ("validity-2")),
         Replacement => (Token => Make_Token ("validity-3")));
      Assert (Frontier_Admissible (H), "Chained correction is admissible");
      Ok := Project_Memory (H, Mem);
      Assert (Ok, "Chained correction projects to memory");
      Find_Occurrence_Date (Mem, Ev1, Found_D, Found);
      Assert (Found and then Equal_Date (Found_D, D3), "Chained correction selects tip date");

      --  4. Sibling conflict: validity-1 -> validity-2 and validity-1 -> validity-4
      declare
         H_Sib : Validity_History := H;
      begin
         H_Sib.Fact_Count := 4;
         H_Sib.Facts (4) := (Id => (Token => Make_Token ("validity-4")), Event_Id => Ev1, Valid_On => D4);
         H_Sib.Correction_Count := 2;
         H_Sib.Corrections (2) :=
           (Id          => (Token => Make_Token ("validity-correction-sib")),
            Target      => (Token => Make_Token ("validity-1")),
            Replacement => (Token => Make_Token ("validity-4")));
         Assert (not Frontier_Admissible (H_Sib), "Sibling date correction fails closed");
         declare
            Dummy_Mem : Validity_Memory;
         begin
            Assert (not Project_Memory (H_Sib, Dummy_Mem), "Sibling conflict rejects memory projection");
         end;
      end;

      --  5. Cross-event correction: validity-1 (Ev1) replaced by validity-x (Ev2)
      declare
         H_Cross : Validity_History;
      begin
         H_Cross.Fact_Count := 2;
         H_Cross.Facts (1) := (Id => (Token => Make_Token ("validity-1")), Event_Id => Ev1, Valid_On => D1);
         H_Cross.Facts (2) := (Id => (Token => Make_Token ("validity-2")), Event_Id => Ev2, Valid_On => D2);
         H_Cross.Correction_Count := 1;
         H_Cross.Corrections (1) :=
           (Id          => (Token => Make_Token ("validity-correction-cross")),
            Target      => (Token => Make_Token ("validity-1")),
            Replacement => (Token => Make_Token ("validity-2")));
         Assert (not Frontier_Admissible (H_Cross), "Cross-event date correction fails closed");
      end;

      --  6. Self-correction / cycle
      declare
         H_Cycle : Validity_History;
      begin
         H_Cycle.Fact_Count := 1;
         H_Cycle.Facts (1) := (Id => (Token => Make_Token ("validity-1")), Event_Id => Ev1, Valid_On => D1);
         H_Cycle.Correction_Count := 1;
         H_Cycle.Corrections (1) :=
           (Id          => (Token => Make_Token ("validity-correction-self")),
            Target      => (Token => Make_Token ("validity-1")),
            Replacement => (Token => Make_Token ("validity-1")));
         Assert (not Frontier_Admissible (H_Cycle), "Self-correction fails closed");
      end;

      --  7. Missing fact reference
      declare
         H_Missing : Validity_History;
      begin
         H_Missing.Fact_Count := 1;
         H_Missing.Facts (1) := (Id => (Token => Make_Token ("validity-1")), Event_Id => Ev1, Valid_On => D1);
         H_Missing.Correction_Count := 1;
         H_Missing.Corrections (1) :=
           (Id          => (Token => Make_Token ("validity-correction-1")),
            Target      => (Token => Make_Token ("validity-1")),
            Replacement => (Token => Make_Token ("validity-ghost")));
         Assert (not Frontier_Admissible (H_Missing), "Dangling replacement reference fails closed");
      end;
   end Test_Frontier_Mechanics;

   ----------------------------------------------------------------------------
   --  Test Suite 2: V2 Round-Trip Persistence
   ----------------------------------------------------------------------------
   procedure Test_V2_Roundtrip is
      Ev1 : constant Event_Id := (Token => Make_Token ("record-1"));
      H_Orig : Validity_History;
      F_Out : File_Type;
      Path  : constant String := Sandbox_Dir & "/v2_test.loam";
   begin
      Ada.Directories.Create_Path (Sandbox_Dir);

      H_Orig.Fact_Count := 3;
      H_Orig.Facts (1) := (Id => Root_Fact_Id (Ev1), Event_Id => Ev1, Valid_On => Make_Date (2026, 9, 3));
      H_Orig.Facts (2) := (Id => (Token => Make_Token ("validity-1")), Event_Id => Ev1, Valid_On => Make_Date (2026, 9, 2));
      H_Orig.Facts (3) := (Id => (Token => Make_Token ("validity-2")), Event_Id => Ev1, Valid_On => Make_Date (2026, 9, 1));

      H_Orig.Correction_Count := 2;
      H_Orig.Corrections (1) :=
        (Id          => (Token => Make_Token ("validity-correction-1")),
         Target      => Root_Fact_Id (Ev1),
         Replacement => (Token => Make_Token ("validity-1")));
      H_Orig.Corrections (2) :=
        (Id          => (Token => Make_Token ("validity-correction-2")),
         Target      => (Token => Make_Token ("validity-1")),
         Replacement => (Token => Make_Token ("validity-2")));

      declare
         Encoded : constant String := Format_Validity_History (H_Orig);
      begin
         Create (F_Out, Out_File, Path);
         Put (F_Out, Encoded);
         Close (F_Out);

         declare
            Read_Res : constant Read_Validity_Result := Read_Validity_File (Path);
            Mem_Date : Date_Type;
            Found    : Boolean;
         begin
            Assert (Read_Res.Success, "V2 formatted file parses successfully");
            Assert_Equal_Int (3, Long_Long_Integer (Read_Res.History.Fact_Count), "3 facts preserved in roundtrip");
            Assert_Equal_Int (2, Long_Long_Integer (Read_Res.History.Correction_Count), "2 corrections preserved in roundtrip");
            Find_Occurrence_Date (Read_Res.Memory, Ev1, Mem_Date, Found);
            Assert (Found and then Equal_Date (Mem_Date, Make_Date (2026, 9, 1)), "Memory resolves tip date 2026-09-01");
         end;
      end;
   end Test_V2_Roundtrip;

   ----------------------------------------------------------------------------
   --  Test Suite 3: Publisher Integration & Manifest Authority
   ----------------------------------------------------------------------------
   procedure Test_Publisher_Integration is
      Receipt : Date_Receipt;
      Before_Current : String (1 .. 10000) := [others => ' '];
      BC_Len : Natural := 0;
   begin
      Setup_Sandbox;

      --  Save exact CURRENT bytes before tests
      declare
         S : constant String := Read_File_String (Authority_Dir & "/CURRENT");
      begin
         BC_Len := S'Length;
         Before_Current (1 .. BC_Len) := S;
      end;

      --  1. Refuse impossible date 2026-02-29
      Receipt := Publish_Date
        (Authority_Dir   => Authority_Dir,
         Correction_Path => Corr_File,
         Target_Str      => "record-1",
         Date_Str        => "2026-02-29");
      Assert (not Receipt.Success, "Impossible date 2026-02-29 refused");
      Assert (Read_File_String (Authority_Dir & "/CURRENT") = Before_Current (1 .. BC_Len),
              "CURRENT untouched after impossible date refusal");

      --  2. Refuse malformed date string
      Receipt := Publish_Date
        (Authority_Dir   => Authority_Dir,
         Correction_Path => Corr_File,
         Target_Str      => "record-1",
         Date_Str        => "not-a-date");
      Assert (not Receipt.Success, "Malformed date string refused");
      Assert (Read_File_String (Authority_Dir & "/CURRENT") = Before_Current (1 .. BC_Len),
              "CURRENT untouched after malformed date refusal");

      --  3. Same-date no-op with 2026-09-04
      Receipt := Publish_Date
        (Authority_Dir   => Authority_Dir,
         Correction_Path => Corr_File,
         Target_Str      => "record-1",
         Date_Str        => "2026-09-04");
      Assert (Receipt.Success, "Same-date publication succeeds as no-op");
      Assert (not Receipt.Changed, "Same-date reports Changed = False");
      Assert (not Receipt.First_Date, "Same-date reports First_Date = False");
      Assert (Receipt.Has_Previous, "Same-date reports Has_Previous = True");
      Assert (Equal_Date (Receipt.Previous, Make_Date (2026, 9, 4)), "Same-date previous matches 2026-09-04");
      Assert (Read_File_String (Authority_Dir & "/CURRENT") = Before_Current (1 .. BC_Len),
              "CURRENT untouched after same-date no-op");

      --  Capture old manifest families before first real date change
      declare
         Old_Man : constant Read_Manifest_Result := Read_Manifest_File (Authority_Dir & "/CURRENT");
      begin
         Assert (Old_Man.Success, "Old manifest loaded");

         --  4. First date correction to 2026-09-03
         Receipt := Publish_Date
           (Authority_Dir   => Authority_Dir,
            Correction_Path => Corr_File,
            Target_Str      => "record-1",
            Date_Str        => "2026-09-03");
         Assert (Receipt.Success, "First date correction succeeds");
         Assert (Receipt.Changed, "First date correction reports Changed = True");
         Assert (not Receipt.First_Date, "First date correction reports First_Date = False");
         Assert (Receipt.Has_Previous, "First date correction reports Has_Previous = True");
         Assert (Equal_Date (Receipt.Previous, Make_Date (2026, 9, 4)), "Previous date was 2026-09-04");
         Assert (Equal_Date (Receipt.Valid_On, Make_Date (2026, 9, 3)), "New date is 2026-09-03");

         --  Verify manifest authority update
         declare
            New_Man : constant Read_Manifest_Result := Read_Manifest_File (Authority_Dir & "/CURRENT");
         begin
            Assert (New_Man.Success, "New manifest loaded after date correction");
            Assert (New_Man.Manifest (Family_Actual_Validity).Digest /=
                    Old_Man.Manifest (Family_Actual_Validity).Digest,
                    "ActualValidity family digest updated");

            --  Verify unchanged families preserved
            for Fam in Manifest_Family loop
               if Fam /= Family_Actual_Validity then
                  Assert (New_Man.Manifest (Fam).Digest = Old_Man.Manifest (Fam).Digest,
                          "Unchanged family preserved: " & Family_Name (Fam));
               end if;
            end loop;
         end;

         --  5. Repeated date correction to 2026-09-02
         Receipt := Publish_Date
           (Authority_Dir   => Authority_Dir,
            Correction_Path => Corr_File,
            Target_Str      => "record-1",
            Date_Str        => "2026-09-02");
         Assert (Receipt.Success, "Repeated date correction succeeds");
         Assert (Receipt.Changed, "Repeated date correction reports Changed = True");
         Assert (Equal_Date (Receipt.Previous, Make_Date (2026, 9, 3)), "Previous date was 2026-09-03");
         Assert (Equal_Date (Receipt.Valid_On, Make_Date (2026, 9, 2)), "New date is 2026-09-02");

         --  6. Movement correction & stale target refusal
         declare
            Draft : constant Correction_Draft :=
              Make_Two_Party_Draft
                (Target      => "record-1",
                 From_Locus  => "cash",
                 To_Locus    => "yucho",
                 Amount      => 2000,
                 Description => "replacement movement");
            Corr_Rec : constant Correction_Receipt :=
              Publish_Correction
                (Authority_Dir   => Authority_Dir,
                 Correction_Path => Corr_File,
                 Reversals_Path  => Rev_File,
                 Draft           => Draft);
         begin
            Assert (Corr_Rec.Success, "Movement correction of record-1 succeeds");
            Assert (Corr_Rec.Replacement.Token.Length > 0, "Replacement allocated");

            --  Stale date correction on superseded record-1 must fail closed
            declare
               Before_Stale : constant String := Read_File_String (Authority_Dir & "/CURRENT");
               Stale_Rec    : constant Date_Receipt :=
                 Publish_Date
                   (Authority_Dir   => Authority_Dir,
                    Correction_Path => Corr_File,
                    Target_Str      => "record-1",
                    Date_Str        => "2026-08-31");
            begin
               Assert (not Stale_Rec.Success, "Date correction on superseded record-1 fails closed");
               Assert (Read_File_String (Authority_Dir & "/CURRENT") = Before_Stale,
                       "CURRENT untouched after stale target refusal");
            end;

            --  Date correction on current replacement event succeeds
            declare
               Repl_Id_Str : constant String :=
                 Corr_Rec.Replacement.Token.Value (1 .. Corr_Rec.Replacement.Token.Length);
               Repl_Date_Rec : constant Date_Receipt :=
                 Publish_Date
                   (Authority_Dir   => Authority_Dir,
                    Correction_Path => Corr_File,
                    Target_Str      => Repl_Id_Str,
                    Date_Str        => "2026-08-31");
            begin
               Assert (Repl_Date_Rec.Success, "Date correction on current replacement succeeds");
               Assert (Repl_Date_Rec.Has_Previous, "Replacement has previous date carried forward");
               Assert (Equal_Date (Repl_Date_Rec.Previous, Make_Date (2026, 9, 2)),
                       "Replacement carried date 2026-09-02 preserved");
               Assert (Equal_Date (Repl_Date_Rec.Valid_On, Make_Date (2026, 8, 31)),
                       "Replacement corrected to 2026-08-31");
            end;
         end;
      end;
   end Test_Publisher_Integration;

   procedure Run is
   begin
      Test_Frontier_Mechanics;
      Test_V2_Roundtrip;
      if Real_Data_Available then
         Test_Publisher_Integration;
      end if;
   end Run;

end Test_Actual_Validity_Publisher;
