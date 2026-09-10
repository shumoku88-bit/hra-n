-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Relation Unit / Discharge Tracking
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Text_IO; use Ada.Text_IO;

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Relation_Reader; use HRA_N.Storage.Relation_Reader;
with HRA_N.Application.Relation_Frontier;
use HRA_N.Application.Relation_Frontier;
with Test_Support; use Test_Support;

package body Test_Relation is

   Sandbox_Dir : constant String := "/tmp/hra_n_test_relation";

   procedure Write_File (Path, Content : String) is
      File : File_Type;
   begin
      Create (File, Out_File, Path);
      Put (File, Content);
      Close (File);
   end Write_File;

   procedure Append_Event
     (Events     : in out Event_Vectors.Vector;
      Event_Name : String;
      Effect_Name: String;
      Amount     : Quanta_Type)
   is
      Effs : Effect_List;
   begin
      Effs.Count := 1;
      Effs.Values (1) :=
        (Key     => (Token => Make_Token (Effect_Name)),
         Locus   => (Token => Make_Token ("cash")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => Amount));
      Events.Append
        (Make_Event ((Token => Make_Token (Event_Name)), Effs));
   end Append_Event;

   function Base_Unit return Relation_Unit is
     ((Id            => Make_Token ("r1"),
       Source_Event  => (Token => Make_Token ("e-source")),
       Source_Effect => (Token => Make_Token ("k1")),
       Debtor        => Household_Endpoint,
       Creditor      => External_Endpoint (Make_Token ("friend")),
       Quantity      => 100));

   procedure Run is
      Units      : Unit_Memory;
      Discharges : Discharge_Memory;
      Events     : Event_Vectors.Vector;
      Projection : Outstanding_Result;
      Value      : Relation_Unit;
      Found      : Boolean;
      HT         : constant Character := ASCII.HT;
      LF         : constant Character := ASCII.LF;
   begin
      ----------------------------------------------------------------------
      --  1. Pure Core vocabulary
      ----------------------------------------------------------------------
      Assert
        (Endpoints_Are_Admissible
           (Household_Endpoint, External_Endpoint (Make_Token ("friend"))),
         "Household-to-external endpoint geometry is admissible");
      Assert
        (Endpoints_Are_Admissible
           (External_Endpoint (Make_Token ("friend")), Household_Endpoint),
         "External-to-household endpoint geometry is admissible");
      Assert
        (not Endpoints_Are_Admissible
           (Household_Endpoint, Household_Endpoint),
         "Household-to-household relation is rejected");
      Assert
        (not Endpoint_Is_Well_Formed (External_Endpoint (Make_Token (""))),
         "Empty external endpoint is not well formed");

      Units.Count := 1;
      Units.Units (1) := Base_Unit;
      Assert (Unit_Ids_Are_Unique (Units), "Single relation id is unique");
      Find_Unit (Units, Make_Token ("r1"), Value, Found);
      Assert (Found and then Value.Quantity = 100, "Find_Unit resolves exact quantity");
      Find_Unit (Units, Make_Token ("absent"), Value, Found);
      Assert (not Found, "Find_Unit reports missing identity honestly");

      ----------------------------------------------------------------------
      --  2. Persistence readers: syntax only, raw semantic evidence retained
      ----------------------------------------------------------------------
      if Ada.Directories.Exists (Sandbox_Dir) then
         Ada.Directories.Delete_Tree (Sandbox_Dir);
      end if;
      Ada.Directories.Create_Path (Sandbox_Dir);

      Write_File
        (Sandbox_Dir & "/units.loam",
         "LOAM-RELATION-UNIT-MEMORY" & HT & "1" & LF &
         "RELATION" & HT & "r1" & HT & "e-source" & HT & "k1" & HT &
         "H" & HT & HT & "E" & HT & "friend" & HT & "100" & LF &
         "RELATION" & HT & "r1" & HT & "e-source" & HT & "k1" & HT &
         "E" & HT & "friend" & HT & "H" & HT & HT & "-5" & LF);
      declare
         Read_Units : constant Unit_Read_Result :=
           Read_Relation_Unit_File (Sandbox_Dir & "/units.loam");
      begin
         Assert (Read_Units.Success, "RelationUnit v1 rows parse");
         Assert (Read_Units.Memory.Count = 2, "Reader retains two raw units");
         Assert (not Unit_Ids_Are_Unique (Read_Units.Memory),
                 "Reader preserves duplicate ids for Application fail-closed admission");
         Assert (Read_Units.Memory.Units (2).Quantity = -5,
                 "Reader preserves raw negative quantity");
      end;

      Write_File
        (Sandbox_Dir & "/bad-endpoint.loam",
         "LOAM-RELATION-UNIT-MEMORY" & HT & "1" & LF &
         "RELATION" & HT & "r1" & HT & "e1" & HT & "k1" & HT &
         "H" & HT & "not-empty" & HT & "E" & HT & "friend" & HT & "1" & LF);
      declare
         Bad : constant Unit_Read_Result :=
           Read_Relation_Unit_File (Sandbox_Dir & "/bad-endpoint.loam");
      begin
         Assert (not Bad.Success and then Bad.Error_Line = 2,
                 "Household endpoint with token is rejected syntactically");
      end;

      Write_File
        (Sandbox_Dir & "/discharges.loam",
         "LOAM-RELATION-DISCHARGE-MEMORY" & HT & "1" & LF &
         "DISCHARGE" & HT & "e-pay" & HT & "r1" & HT & "40" & LF &
         "DISCHARGE" & HT & "e-pay" & HT & "r1" & HT & "-1" & LF);
      declare
         Read_Dis : constant Discharge_Read_Result :=
           Read_Relation_Discharge_File (Sandbox_Dir & "/discharges.loam");
      begin
         Assert (Read_Dis.Success, "RelationDischarge v1 rows parse");
         Assert (Read_Dis.Memory.Count = 2, "Reader retains two raw discharges");
         Assert (not Discharge_Pairs_Are_Unique (Read_Dis.Memory),
                 "Reader preserves duplicate discharge pairs");
         Assert (Read_Dis.Memory.Discharges (2).Quantity = -1,
                 "Reader preserves raw negative discharge quantity");
      end;

      Write_File (Sandbox_Dir & "/bad-header.loam", "BAD" & LF);
      declare
         Bad : constant Unit_Read_Result :=
           Read_Relation_Unit_File (Sandbox_Dir & "/bad-header.loam");
      begin
         Assert (not Bad.Success and then Bad.Error_Line = 1,
                 "Unsupported RelationUnit header is rejected");
      end;

      ----------------------------------------------------------------------
      --  3. Application admission and exact outstanding projection
      ----------------------------------------------------------------------
      Units := (others => <>);
      Discharges := (others => <>);
      Events.Clear;
      Units.Count := 1;
      Units.Units (1) := Base_Unit;
      Append_Event (Events, "e-source", "k1", -100);
      Append_Event (Events, "e-pay", "pay", 40);

      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Relation_Open, "Admitted relation projects open state");
      Assert (Projection.Outstanding_Quantity = 100,
              "No discharge preserves full outstanding quantity");
      Assert (Equal_Token (Projection.Measure.Token, Make_Token ("jpy")),
              "Relation inherits measure from source Effect");

      Discharges.Count := 2;
      Discharges.Discharges (1) :=
        (Event => (Token => Make_Token ("e-pay")),
         Target => Make_Token ("r1"), Quantity => 40);
      Discharges.Discharges (2) :=
        (Event => (Token => Make_Token ("e-future")),
         Target => Make_Token ("r1"), Quantity => 20);
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Relation_Open and then Projection.Outstanding_Quantity = 60,
              "Present later Event activates exact discharge");
      Assert (Projection.Admitted_Discharge_Count = 1,
              "Missing later Event remains inert crash residue");

      Append_Event (Events, "e-future", "pay2", 20);
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.Outstanding_Quantity = 40
              and then Projection.Discharged_Quantity = 60,
              "Previously inert discharge activates when Event appears");

      Discharges.Count := 1;
      Discharges.Discharges (1).Quantity := 100;
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Relation_Discharged
              and then Projection.Outstanding_Quantity = 0,
              "Exact full discharge projects discharged state");

      Discharges.Count := 2;
      Discharges.Discharges (1) :=
        (Event => (Token => Make_Token ("e-pay")),
         Target => Make_Token ("r1"), Quantity => 40);
      Discharges.Discharges (2) :=
        (Event => (Token => Make_Token ("e-pay")),
         Target => Make_Token ("r1"), Quantity => 20);
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Evidence_Unresolved,
              "Duplicate active Event-target discharge fails closed");

      Discharges.Discharges (2).Event := (Token => Make_Token ("e-future"));
      Discharges.Discharges (1).Quantity := 60;
      Discharges.Discharges (2).Quantity := 50;
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Evidence_Unresolved,
              "Aggregate over-discharge fails closed without overflow");

      Discharges.Count := 1;
      Discharges.Discharges (1) :=
        (Event => (Token => Make_Token ("e-source")),
         Target => Make_Token ("r1"), Quantity => 10);
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Evidence_Unresolved,
              "Source Event cannot discharge its own relation");

      Discharges := (others => <>);
      Units.Units (1).Debtor := Household_Endpoint;
      Units.Units (1).Creditor := Household_Endpoint;
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Evidence_Unresolved,
              "Invalid endpoint geometry fails closed");

      Units.Units (1) := Base_Unit;
      Units.Units (1).Quantity := 50;
      Units.Count := 2;
      Units.Units (2) := Base_Unit;
      Units.Units (2).Id := Make_Token ("r2");
      Units.Units (2).Quantity := 60;
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Evidence_Unresolved,
              "Aggregate relation-plane coverage above source magnitude fails closed");

      Units.Units (2).Id := Make_Token ("r1");
      Units.Units (2).Quantity := 10;
      Project_Outstanding (Events, Units, Discharges, Make_Token ("r1"), Projection);
      Assert (Projection.State = Evidence_Unresolved,
              "Duplicate relation identity fails closed globally");

      Units.Count := 1;
      Units.Units (1) := Base_Unit;
      Project_Outstanding (Events, Units, Discharges, Make_Token ("absent"), Projection);
      Assert (Projection.State = Target_Absent,
              "Absent relation target is distinct from unresolved evidence");

      ----------------------------------------------------------------------
      --  4. Production manifest objects (currently valid empty memories)
      ----------------------------------------------------------------------
      if Real_Data_Available then
         declare
            Man : constant Read_Manifest_Result :=
              Read_Manifest_File (Real_Data_Dir & "/movement-authority/CURRENT");
         begin
            Assert (Man.Success, "Production manifest loads for relation objects");
            declare
               U_Item : constant Manifest_Item := Man.Manifest (Family_Relation_Unit);
               D_Item : constant Manifest_Item := Man.Manifest (Family_Relation_Discharge);
               U_Read : constant Unit_Read_Result := Read_Relation_Unit_File
                 (Real_Data_Dir & "/movement-authority/" &
                  U_Item.Rel_Path (1 .. U_Item.Path_Len));
               D_Read : constant Discharge_Read_Result := Read_Relation_Discharge_File
                 (Real_Data_Dir & "/movement-authority/" &
                  D_Item.Rel_Path (1 .. D_Item.Path_Len));
            begin
               Assert (U_Item.Present and then D_Item.Present,
                       "Manifest declares both relation families");
               Assert (U_Read.Success and then U_Read.Memory.Count = 0,
                       "Production RelationUnit empty memory parses");
               Assert (D_Read.Success and then D_Read.Memory.Count = 0,
                       "Production RelationDischarge empty memory parses");
            end;
         end;
      end if;
   end Run;

end Test_Relation;
