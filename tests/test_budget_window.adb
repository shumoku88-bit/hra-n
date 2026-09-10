-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Envelope Budget Window Projection Engine
-------------------------------------------------------------------------------

with Test_Support;                 use Test_Support;
with HRA_N.Core.Types;             use HRA_N.Core.Types;
with HRA_N.Core.Event;             use HRA_N.Core.Event;
with HRA_N.Core.Capacity;          use HRA_N.Core.Capacity;
with HRA_N.Core.Actual_Routing;    use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Validity;          use HRA_N.Core.Validity;
with HRA_N.Storage.Capacity_Reader; use HRA_N.Storage.Capacity_Reader;
with HRA_N.Storage.Actual_Routing_Reader; use HRA_N.Storage.Actual_Routing_Reader;
with HRA_N.Storage.Boundary_Presets_Reader; use HRA_N.Storage.Boundary_Presets_Reader;
with HRA_N.Storage.Manifest;       use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader;   use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Validity_Reader; use HRA_N.Storage.Validity_Reader;
with HRA_N.Application.Budget_Window; use HRA_N.Application.Budget_Window;

package body Test_Budget_Window is

   function Make_Simple_Event
     (Ev_Id_Str : String;
      Locus_Str : String;
      Quanta    : Quanta_Type) return Event
   is
      Effects : Effect_List;
      Eff     : Effect;
   begin
      Effects.Count := 1;
      Eff.Key.Token     := Make_Token ("eff-1");
      Eff.Locus.Token   := Make_Token (Locus_Str);
      Eff.Measure.Token := Make_Token ("jpy");
      Eff.Amount.Quanta := Quanta;
      Effects.Values (1) := Eff;

      return Make_Event (Event_Id'(Token => Make_Token (Ev_Id_Str)), Effects);
   end Make_Simple_Event;

   procedure Run is
   begin
      --  1. Synthetic Mock Envelope Budget Verification
      declare
         Mock_Cap     : Capacity_Memory;
         Mock_Events  : Event_Vectors.Vector;
         Mock_Val_List: Validity_Entry_List;
         Mock_Val_Mem : Validity_Memory;
         Mock_Routing : Routing_Map;
         Rep          : Budget_Window_Report;
      begin
         --  Capacity Movement 1: Allocate 50,000 JPY to Food
         Mock_Cap.Movement_Count := 1;
         Mock_Cap.Movements (1) :=
           (Id           => Make_Token ("cap-1"),
            Currency     => Make_Token ("jpy"),
            Change_Count => 2,
            Changes      =>
              [1 => (Coord => Make_Unallocated_Coordinate, Amount => -50_000),
               2 => (Coord => Make_Purpose_Coordinate (Make_Token ("food")), Amount => 50_000),
               others => Empty_Change]);

         Mock_Cap.Effective_Count := 1;
         Mock_Cap.Effective (1) :=
           (Movement_Id => Make_Token ("cap-1"),
            Year        => 2026,
            Month       => 9,
            Day         => 1);

         --  Capacity Movement 2: Transfer 5,000 JPY from Food to Books
         Mock_Cap.Movement_Count := 2;
         Mock_Cap.Movements (2) :=
           (Id           => Make_Token ("cap-2"),
            Currency     => Make_Token ("jpy"),
            Change_Count => 2,
            Changes      =>
              [1 => (Coord => Make_Purpose_Coordinate (Make_Token ("food")), Amount => -5_000),
               2 => (Coord => Make_Purpose_Coordinate (Make_Token ("books")), Amount => 5_000),
               others => Empty_Change]);

         Mock_Cap.Effective_Count := 2;
         Mock_Cap.Effective (2) :=
           (Movement_Id => Make_Token ("cap-2"),
            Year        => 2026,
            Month       => 9,
            Day         => 5);

         Assert (All_Movements_Conserved (Mock_Cap), "Mock capacity movements conserved");
         Assert (Effective_Evidence_Complete (Mock_Cap), "Mock capacity effective complete");

         --  Routing: grocery -> food, comic -> books
         Mock_Routing.Count := 2;
         Mock_Routing.Entries (1) :=
           (Locus => (Token => Make_Token ("grocery")), Purpose => Make_Token ("food"));
         Mock_Routing.Entries (2) :=
           (Locus => (Token => Make_Token ("comic")), Purpose => Make_Token ("books"));

         --  Events & Validity
         --  Event 1: grocery +12,000 on 2026-09-02
         Mock_Events.Append (Make_Simple_Event ("ev-1", "grocery", 12_000));
         Mock_Val_List.Count := 1;
         Mock_Val_List.Values (1) :=
           (Event_Id => (Token => Make_Token ("ev-1")),
            Valid_On => (Year => 2026, Month => 9, Day => 2));

         --  Event 2: comic +3,000 on 2026-09-10
         Mock_Events.Append (Make_Simple_Event ("ev-2", "comic", 3_000));
         Mock_Val_List.Count := 2;
         Mock_Val_List.Values (2) :=
           (Event_Id => (Token => Make_Token ("ev-2")),
            Valid_On => (Year => 2026, Month => 9, Day => 10));

         --  Event 3: comic +1,000 on 2026-10-05 (OUTSIDE WINDOW!)
         Mock_Events.Append (Make_Simple_Event ("ev-3", "comic", 1_000));
         Mock_Val_List.Count := 3;
         Mock_Val_List.Values (3) :=
           (Event_Id => (Token => Make_Token ("ev-3")),
            Valid_On => (Year => 2026, Month => 10, Day => 5));

         Mock_Val_Mem := Make_Validity_Memory (Mock_Val_List);

         --  Project over [2026-09-01, 2026-10-01)
         Project_Budget_Window
           (Capacity_Mem => Mock_Cap,
            Events       => Mock_Events,
            Validities   => Mock_Val_Mem,
            Routing      => Mock_Routing,
            Start_Y      => 2026,
            Start_M      => 9,
            Start_D      => 1,
            End_Y        => 2026,
            End_M        => 10,
            End_D        => 1,
            Report       => Rep);

         Assert_Equal_Int (2, Long_Long_Integer (Rep.Row_Count), "Mock projected 2 purposes");
         Assert (Universal_Capacity_Holds (Rep), "Mock universal capacity conservation holds");
         Assert_Equal_Int (0, Rep.Capacity_Sum, "Mock capacity sum is strictly 0");
         Assert_Equal_Int (-50_000, Long_Long_Integer (Rep.Unallocated_Funds), "Mock unallocated funds is -50,000");

         --  Food: 50,000 - 5,000 = 45,000 Entitlement, 12,000 Consumption, 33,000 Remaining
         Assert_Equal_Int (45_000, Long_Long_Integer (Rep.Rows (1).Entitlement), "Food entitlement is 45,000");
         Assert_Equal_Int (12_000, Long_Long_Integer (Rep.Rows (1).Consumption), "Food consumption is 12,000");
         Assert_Equal_Int (33_000, Long_Long_Integer (Rep.Rows (1).Remaining), "Food remaining is 33,000");

         --  Books: 5,000 Entitlement, 3,000 Consumption (event-3 excluded!), 2,000 Remaining
         Assert_Equal_Int (5_000, Long_Long_Integer (Rep.Rows (2).Entitlement), "Books entitlement is 5,000");
         Assert_Equal_Int (3_000, Long_Long_Integer (Rep.Rows (2).Consumption), "Books consumption excludes out-of-window event");
         Assert_Equal_Int (2_000, Long_Long_Integer (Rep.Rows (2).Remaining), "Books remaining is 2,000");
      end;

      --  2. Real Production Household Authority Ground Truth Verification
      if Real_Data_Available then
         declare
            Cap_Path   : constant String := Real_Data_Dir & "/capacity.loam";
            Eff_Path   : constant String := Real_Data_Dir & "/capacity.loam.effective";
            Rout_Path  : constant String := Real_Data_Dir & "/actual-routing.loam";
            Pres_Path  : constant String := Real_Data_Dir & "/config/boundary-presets.tsv";

            Cap_Res    : constant HRA_N.Storage.Capacity_Reader.Read_Result :=
              Read_Capacity_Files (Cap_Path, Eff_Path);
            Rout_Res   : constant HRA_N.Storage.Actual_Routing_Reader.Read_Result :=
              Read_Actual_Routing_File (Rout_Path);
            Pres_Res   : constant HRA_N.Storage.Boundary_Presets_Reader.Read_Result :=
              Read_Boundary_Presets_File (Pres_Path);

            Manifest_Res : constant Read_Manifest_Result :=
              Read_Manifest_File (Real_Data_Dir & "/movement-authority/CURRENT");
            Event_Full   : constant String :=
              Real_Data_Dir & "/movement-authority/" &
              Manifest_Res.Manifest (Family_Event).Rel_Path
                (1 .. Manifest_Res.Manifest (Family_Event).Path_Len);
            Val_Full     : constant String :=
              Real_Data_Dir & "/movement-authority/" &
              Manifest_Res.Manifest (Family_Actual_Validity).Rel_Path
                (1 .. Manifest_Res.Manifest (Family_Actual_Validity).Path_Len);

            Event_Res    : constant HRA_N.Storage.Event_Reader.Read_Result :=
              Read_Event_Memory_File (Event_Full);
            Val_Res      : constant HRA_N.Storage.Validity_Reader.Read_Validity_Result :=
              Read_Validity_File (Val_Full);

            Rep          : Budget_Window_Report;
         begin
            Assert (Cap_Res.Success, "Real capacity files loaded successfully");
            Assert_Equal_Int (18, Long_Long_Integer (Cap_Res.Memory.Movement_Count), "Exact 18 capacity movements loaded");
            Assert_Equal_Int (18, Long_Long_Integer (Cap_Res.Memory.Effective_Count), "Exact 18 capacity effective dates loaded");
            Assert (All_Movements_Conserved (Cap_Res.Memory), "All real capacity movements conserved");
            Assert (Effective_Evidence_Complete (Cap_Res.Memory), "Real capacity effective evidence complete");

            Assert (Rout_Res.Success, "Real actual routing loaded successfully");
            Assert_Equal_Int (22, Long_Long_Integer (Rout_Res.Map.Count), "Exact 22 actual routing rules loaded");

            Assert (Pres_Res.Success, "Real boundary presets loaded successfully");
            Assert_Equal_Int (1, Long_Long_Integer (Pres_Res.Memory.Count), "Exact 1 boundary preset loaded");
            Assert (Pres_Res.Memory.Presets (1).Name.Length = 7
                    and then Pres_Res.Memory.Presets (1).Name.Value (1 .. 7) = "Pension",
                    "Preset is Pension");

            Assert (Manifest_Res.Success, "Real manifest loaded for budget test");
            Assert (Event_Res.Success, "Real event memory loaded for budget test");
            Assert (Val_Res.Success, "Real validity memory loaded for budget test");

            --  Project over Pension window: [2026-08-14, 2026-10-15)
            Project_Budget_Window
              (Capacity_Mem => Cap_Res.Memory,
               Events       => Event_Res.Events,
               Validities   => Val_Res.Memory,
               Routing      => Rout_Res.Map,
               Start_Y      => 2026,
               Start_M      => 8,
               Start_D      => 14,
               End_Y        => 2026,
               End_M        => 10,
               End_D        => 15,
               Report       => Rep);

            Assert (Universal_Capacity_Holds (Rep), "Real universal capacity conservation holds");
            Assert_Equal_Int (0, Rep.Capacity_Sum, "Real capacity delta is strictly 0");
            Assert_Equal_Int (7, Long_Long_Integer (Rep.Row_Count), "Exact 7 remembered purposes projected");

            --  Subtotals verification (Gold ground truth from Loam Lean 4 production)
            Assert_Equal_Int (127_508, Long_Long_Integer (Rep.Total_Entitlement), "Total entitlement matches Loam (127,508 JPY)");
            Assert_Equal_Int (92_222, Long_Long_Integer (Rep.Total_Consumption), "Total consumption matches Loam (92,222 JPY)");
            Assert_Equal_Int (35_286, Long_Long_Integer (Rep.Total_Remaining), "Total remaining matches Loam (35,286 JPY)");
            Assert_Equal_Int (-127_508, Long_Long_Integer (Rep.Unallocated_Funds), "Total unallocated matches (-127,508 JPY)");

            --  Purpose-level verification (Exact match to 1 JPY)
            --  Row 1: Food (39,100 / 22,599 / 16,501)
            Assert_Equal_Int (39_100, Long_Long_Integer (Rep.Rows (1).Entitlement), "Row 1 Food entitlement matches Loam");
            Assert_Equal_Int (22_599, Long_Long_Integer (Rep.Rows (1).Consumption), "Row 1 Food consumption matches Loam");
            Assert_Equal_Int (16_501, Long_Long_Integer (Rep.Rows (1).Remaining), "Row 1 Food remaining matches Loam");

            --  Row 2: Food:Stock (8,180 / 8,180 / 0)
            Assert_Equal_Int (8_180, Long_Long_Integer (Rep.Rows (2).Entitlement), "Row 2 Food:Stock entitlement matches Loam");
            Assert_Equal_Int (8_180, Long_Long_Integer (Rep.Rows (2).Consumption), "Row 2 Food:Stock consumption matches Loam");
            Assert_Equal_Int (0, Long_Long_Integer (Rep.Rows (2).Remaining), "Row 2 Food:Stock remaining matches Loam");

            --  Row 3: General Living (27,892 / 33,457 / -5,565 OVERSPENT)
            Assert_Equal_Int (27_892, Long_Long_Integer (Rep.Rows (3).Entitlement), "Row 3 General Living entitlement matches Loam");
            Assert_Equal_Int (33_457, Long_Long_Integer (Rep.Rows (3).Consumption), "Row 3 General Living consumption matches Loam");
            Assert_Equal_Int (-5_565, Long_Long_Integer (Rep.Rows (3).Remaining), "Row 3 General Living remaining matches Loam (-5,565 JPY)");

            --  Row 4: Tobacco (29,500 / 14,000 / 15,500)
            Assert_Equal_Int (29_500, Long_Long_Integer (Rep.Rows (4).Entitlement), "Row 4 Tobacco entitlement matches Loam");
            Assert_Equal_Int (14_000, Long_Long_Integer (Rep.Rows (4).Consumption), "Row 4 Tobacco consumption matches Loam");
            Assert_Equal_Int (15_500, Long_Long_Integer (Rep.Rows (4).Remaining), "Row 4 Tobacco remaining matches Loam");

            --  Row 5: Fixed Expenses (20,936 / 13,496 / 7,440)
            Assert_Equal_Int (20_936, Long_Long_Integer (Rep.Rows (5).Entitlement), "Row 5 Fixed Expenses entitlement matches Loam");
            Assert_Equal_Int (13_496, Long_Long_Integer (Rep.Rows (5).Consumption), "Row 5 Fixed Expenses consumption matches Loam");
            Assert_Equal_Int (7_440, Long_Long_Integer (Rep.Rows (5).Remaining), "Row 5 Fixed Expenses remaining matches Loam");

            --  Row 6: Medical (1,900 / 490 / 1,410)
            Assert_Equal_Int (1_900, Long_Long_Integer (Rep.Rows (6).Entitlement), "Row 6 Medical entitlement matches Loam");
            Assert_Equal_Int (490, Long_Long_Integer (Rep.Rows (6).Consumption), "Row 6 Medical consumption matches Loam");
            Assert_Equal_Int (1_410, Long_Long_Integer (Rep.Rows (6).Remaining), "Row 6 Medical remaining matches Loam");

            --  Row 7: Yucho Savings (0 / 0 / 0)
            Assert_Equal_Int (0, Long_Long_Integer (Rep.Rows (7).Entitlement), "Row 7 Yucho Savings entitlement matches Loam");
            Assert_Equal_Int (0, Long_Long_Integer (Rep.Rows (7).Consumption), "Row 7 Yucho Savings consumption matches Loam");
            Assert_Equal_Int (0, Long_Long_Integer (Rep.Rows (7).Remaining), "Row 7 Yucho Savings remaining matches Loam");
         end;
      end if;
   end Run;

end Test_Budget_Window;
