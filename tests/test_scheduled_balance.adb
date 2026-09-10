-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Scheduled Balance Effects, Day Evidence & Replacement
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Directories;
with GNAT.OS_Lib;

with Test_Support;                          use Test_Support;
with HRA_N.Core.Types;                      use HRA_N.Core.Types;
with HRA_N.Core.Validity;                   use HRA_N.Core.Validity;
with HRA_N.Core.Coverage;                   use HRA_N.Core.Coverage;
with HRA_N.Core.Scheduled;                  use HRA_N.Core.Scheduled;
with HRA_N.Core.Event;                      use HRA_N.Core.Event;
with HRA_N.Storage.Event_Reader;            use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Scheduled_Reader;        use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Scheduled_Writer;        use HRA_N.Storage.Scheduled_Writer;
with HRA_N.Storage.Balance_View_Reader;     use HRA_N.Storage.Balance_View_Reader;
with HRA_N.Application.Scheduled_Inspection; use HRA_N.Application.Scheduled_Inspection;
with HRA_N.Application.Scheduled_Replacement_Publisher; use HRA_N.Application.Scheduled_Replacement_Publisher;

package body Test_Scheduled_Balance is

   Sandbox_Dir   : constant String := "/tmp/hra_n_test_scheduled_balance_sandbox";
   Sandbox_Auth  : constant String := Sandbox_Dir & "/movement-authority";
   Sandbox_Sched : constant String := Sandbox_Dir & "/scheduled.loam";
   function Source_Auth return String is (Real_Data_Dir & "/movement-authority");
   function Source_Sched return String is (Real_Data_Dir & "/scheduled.loam");

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

      Ada.Directories.Create_Path (Sandbox_Dir);
      Ada.Directories.Create_Path (Sandbox_Auth);
      Args (1) := new String'("-R");
      Args (2) := new String'(Source_Auth & "/");
      Args (3) := new String'(Sandbox_Auth);
      GNAT.OS_Lib.Spawn
        (Program_Name => "/bin/cp",
         Args         => Args (1 .. 3),
         Success      => Success);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      GNAT.OS_Lib.Free (Args (3));

      Ada.Directories.Copy_File (Source_Sched, Sandbox_Sched);
   end Setup_Sandbox;

   function Make_2Party_Occ
     (Id_Str   : String;
      Year     : Year_Type;
      Month    : Month_Type;
      Day      : Day_Type;
      From_Loc : String;
      To_Loc   : String;
      Amount   : Quanta_Type;
      Measure  : String := "jpy") return Scheduled_Occurrence
   is
      Occ : Scheduled_Occurrence;
   begin
      Occ.Id           := (Token => Make_Token (Id_Str));
      Occ.Expected_Day := (Year => Year, Month => Month, Day => Day);
      Occ.Measure      := (Token => Make_Token (Measure));
      Occ.Changes.Count := 2;
      Occ.Changes.Values (1) := (Locus => (Token => Make_Token (From_Loc)), Amount => -Amount);
      Occ.Changes.Values (2) := (Locus => (Token => Make_Token (To_Loc)), Amount => Amount);
      return Occ;
   end Make_2Party_Occ;

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
      -- =========================================================================
      --  1. Balance View Reader Tests
      -- =========================================================================
      declare
         Tmp_File : constant String := "/tmp/test_balance_view.tsv";
         File     : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Tmp_File);
         Ada.Text_IO.Put_Line (File, "# Balance view coordinates configuration");
         Ada.Text_IO.Put_Line (File, "");
         Ada.Text_IO.Put_Line (File, "bank" & ASCII.HT & "jpy");
         Ada.Text_IO.Put_Line (File, "wallet" & ASCII.HT & "jpy");
         Ada.Text_IO.Put_Line (File, "# Duplicate should be normalized");
         Ada.Text_IO.Put_Line (File, "bank" & ASCII.HT & "jpy");
         Ada.Text_IO.Put_Line (File, "yucho" & ASCII.HT & "jpy");
         Ada.Text_IO.Close (File);

         declare
            Res : constant Read_Balance_View_Result := Read_Balance_View_File (Tmp_File);
         begin
            Assert (Res.Success, "Balance view reader parses valid tsv with comments and whitespace");
            Assert_Equal_Int (3, Long_Long_Integer (Res.Coordinates.Count), "Duplicate coordinate normalized to 3 entries");
            Assert (Equal_Token (Res.Coordinates.Values (1).Locus.Token, Make_Token ("bank")), "First coordinate is bank");
            Assert (Equal_Token (Res.Coordinates.Values (2).Locus.Token, Make_Token ("wallet")), "Second coordinate is wallet");
            Assert (Equal_Token (Res.Coordinates.Values (3).Locus.Token, Make_Token ("yucho")), "Third coordinate is yucho");
         end;

         if Ada.Directories.Exists (Tmp_File) then
            Ada.Directories.Delete_File (Tmp_File);
         end if;
      end;

      --  Missing balance view file returns empty list (fail-closed, empty question)
      declare
         Res : constant Read_Balance_View_Result := Read_Balance_View_File ("/tmp/nonexistent_bv.tsv");
      begin
         Assert (Res.Success, "Missing balance view file returns Success = True");
         Assert_Equal_Int (0, Long_Long_Integer (Res.Coordinates.Count), "Missing balance view returns empty list");
      end;

      --  Malformed balance view row (too many columns)
      declare
         Tmp_Bad : constant String := "/tmp/test_bad_bv.tsv";
         File    : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Tmp_Bad);
         Ada.Text_IO.Put_Line (File, "bank" & ASCII.HT & "jpy" & ASCII.HT & "extra");
         Ada.Text_IO.Close (File);

         declare
            Res : constant Read_Balance_View_Result := Read_Balance_View_File (Tmp_Bad);
         begin
            Assert (not Res.Success, "Too many columns fails closed");
         end;

         if Ada.Directories.Exists (Tmp_Bad) then
            Ada.Directories.Delete_File (Tmp_Bad);
         end if;
      end;

      -- =========================================================================
      --  2. Scheduled Inspection Lifecycle & Graph Tests
      -- =========================================================================
      declare
         Life   : Scheduled_Lifecycle;
         Events : Event_Vectors.Vector;
      begin
         --  Empty lifecycle -> 0 open occurrences, Status_Ok
         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Ok, "Empty lifecycle projects Status_Ok");
            Assert_Equal_Int (0, Long_Long_Integer (Open_Res.Count), "Empty lifecycle has 0 open occurrences");
         end;

         --  Add s1 and s2
         Life.Sched_Count := 2;
         Life.Sched_Items (1) := Make_2Party_Occ ("s1", 2026, 9, 10, "bank", "wallet", 100);
         Life.Sched_Items (2) := Make_2Party_Occ ("s2", 2026, 9, 11, "bank", "rent", 500);

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Ok, "Two open occurrences project Status_Ok");
            Assert_Equal_Int (2, Long_Long_Integer (Open_Res.Count), "Both occurrences are open");
         end;

         --  Interrupted completion: completion references actual-1, but actual-1 not in Events
         Life.Comp_Count := 1;
         Life.Comp_Items (1) :=
           (Scheduled => (Token => Make_Token ("s1")),
            Actual    => (Token => Make_Token ("actual-1")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Ok, "Interrupted completion projects Status_Ok");
            Assert_Equal_Int (2, Long_Long_Integer (Open_Res.Count),
              "Interrupted completion leaves occurrence s1 open (not effective without actual event)");
         end;

         --  Now confirm actual-1 into Events -> s1 is effectively completed!
         Events.Append (Make_Simple_Event ("actual-1", "bank", -100));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Ok, "Effective completion projects Status_Ok");
            Assert_Equal_Int (1, Long_Long_Integer (Open_Res.Count), "Completed s1 excluded, only s2 remains open");
            Assert (Equal_Token (Open_Res.Occurrences (1).Id.Token, Make_Token ("s2")), "Remaining open is s2");
         end;

         --  Retirement: retire s2
         Life.Ret_Count := 1;
         Life.Ret_Items (1) := (Scheduled => (Token => Make_Token ("s2")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Ok, "Retired s2 projects Status_Ok");
            Assert_Equal_Int (0, Long_Long_Integer (Open_Res.Count), "Both s1 (completed) and s2 (retired) are closed");
         end;
      end;

      --  Replacement chain test: s1 -> s2 -> s3
      declare
         Life   : Scheduled_Lifecycle;
         Events : Event_Vectors.Vector;
      begin
         Life.Sched_Count := 3;
         Life.Sched_Items (1) := Make_2Party_Occ ("s1", 2026, 9, 10, "bank", "wallet", 100);
         Life.Sched_Items (2) := Make_2Party_Occ ("s2", 2026, 9, 11, "bank", "wallet", 110);
         Life.Sched_Items (3) := Make_2Party_Occ ("s3", 2026, 9, 12, "bank", "wallet", 120);

         Life.Repl_Count := 2;
         Life.Repl_Items (1) := (Original => (Token => Make_Token ("s1")), Replaced_By => (Token => Make_Token ("s2")));
         Life.Repl_Items (2) := (Original => (Token => Make_Token ("s2")), Replaced_By => (Token => Make_Token ("s3")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Ok, "Replacement chain projects Status_Ok");
            Assert_Equal_Int (1, Long_Long_Integer (Open_Res.Count), "Only tip of replacement chain s3 is open");
            Assert (Equal_Token (Open_Res.Occurrences (1).Id.Token, Make_Token ("s3")), "s3 is open");
         end;

         --  Cycle detection: s3 -> s1 (cycle: s1 -> s2 -> s3 -> s1)
         Life.Repl_Count := 3;
         Life.Repl_Items (3) := (Original => (Token => Make_Token ("s3")), Replaced_By => (Token => Make_Token ("s1")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Invalid_Replacement_Graph, "Cyclic replacement graph fails closed");
         end;

         --  Self-loop: s1 -> s1
         Life.Repl_Count := 1;
         Life.Repl_Items (1) := (Original => (Token => Make_Token ("s1")), Replaced_By => (Token => Make_Token ("s1")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Invalid_Replacement_Graph, "Self-replacement cycle fails closed");
         end;
      end;

      --  Terminal conflict test: occurrence both completed and retired
      declare
         Life   : Scheduled_Lifecycle;
         Events : Event_Vectors.Vector;
      begin
         Life.Sched_Count := 1;
         Life.Sched_Items (1) := Make_2Party_Occ ("s1", 2026, 9, 10, "bank", "wallet", 100);

         Life.Comp_Count := 1;
         Life.Comp_Items (1) := (Scheduled => (Token => Make_Token ("s1")), Actual => (Token => Make_Token ("act-1")));
         Life.Ret_Count := 1;
         Life.Ret_Items (1) := (Scheduled => (Token => Make_Token ("s1")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Conflicting_Terminal_Evidence,
              "Conflicting completion and retirement fails closed");
         end;
      end;

      --  Terminal conflict: occurrence both retired and replaced
      declare
         Life   : Scheduled_Lifecycle;
         Events : Event_Vectors.Vector;
      begin
         Life.Sched_Count := 2;
         Life.Sched_Items (1) := Make_2Party_Occ ("s1", 2026, 9, 10, "bank", "wallet", 100);
         Life.Sched_Items (2) := Make_2Party_Occ ("s2", 2026, 9, 11, "bank", "wallet", 100);

         Life.Ret_Count := 1;
         Life.Ret_Items (1) := (Scheduled => (Token => Make_Token ("s1")));
         Life.Repl_Count := 1;
         Life.Repl_Items (1) := (Original => (Token => Make_Token ("s1")), Replaced_By => (Token => Make_Token ("s2")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Conflicting_Terminal_Evidence,
              "Conflicting retirement and replacement fails closed");
         end;
      end;

      --  Dangling replacement endpoint: points to unknown scheduled id
      declare
         Life   : Scheduled_Lifecycle;
         Events : Event_Vectors.Vector;
      begin
         Life.Sched_Count := 1;
         Life.Sched_Items (1) := Make_2Party_Occ ("s1", 2026, 9, 10, "bank", "wallet", 100);

         Life.Repl_Count := 1;
         Life.Repl_Items (1) := (Original => (Token => Make_Token ("s1")), Replaced_By => (Token => Make_Token ("unknown-id")));

         declare
            Open_Res : constant Open_Occurrences_Result := Current_Open_Scheduled (Life, Events);
         begin
            Assert (Open_Res.Status = Status_Unknown_Replacement_Scheduled,
              "Replacement pointing to unknown id fails closed");
         end;
      end;

      -- =========================================================================
      --  3. Loam Exact Fixture Test (ScheduledBalanceProjection.lean)
      -- =========================================================================
      declare
         Life   : Scheduled_Lifecycle;
         Events : Event_Vectors.Vector;
         Coords : Balance_Coordinate_List;
      begin
         --  Loam fixture:
         --  payment:   scheduled-payment,   day 2, bank -30, rent 30
         --  transfer:  scheduled-transfer,  day 3, bank -20, wallet 20
         --  boundary:  scheduled-boundary,  day 4, bank -40, rent 40 (end-exclusive excludes this)
         --  overdue:   scheduled-overdue,   day 0, bank -5,  wallet 5
         --  retired:   scheduled-retired,   day 2, bank -6,  wallet 6
         --  completed: scheduled-completed, day 2, bank -9,  wallet 9
         Life.Sched_Count := 6;
         Life.Sched_Items (1) := Make_2Party_Occ ("scheduled-payment", 2026, 1, 3, "bank", "rent", 30);
         Life.Sched_Items (2) := Make_2Party_Occ ("scheduled-transfer", 2026, 1, 4, "bank", "wallet", 20);
         Life.Sched_Items (3) := Make_2Party_Occ ("scheduled-boundary", 2026, 1, 5, "bank", "rent", 40);
         Life.Sched_Items (4) := Make_2Party_Occ ("scheduled-overdue", 2026, 1, 1, "bank", "wallet", 5);
         Life.Sched_Items (5) := Make_2Party_Occ ("scheduled-retired", 2026, 1, 3, "bank", "wallet", 6);
         Life.Sched_Items (6) := Make_2Party_Occ ("scheduled-completed", 2026, 1, 3, "bank", "wallet", 9);

         --  actual-1 confirms completion
         Events.Append (Make_Simple_Event ("actual-1", "bank", -9));

         Life.Comp_Count := 1;
         Life.Comp_Items (1) :=
           (Scheduled => (Token => Make_Token ("scheduled-completed")),
            Actual    => (Token => Make_Token ("actual-1")));

         Life.Ret_Count := 1;
         Life.Ret_Items (1) := (Scheduled => (Token => Make_Token ("scheduled-retired")));

         --  Coordinates with duplicate bank: [bank, wallet, bank, yucho]
         Coords.Count := 4;
         Coords.Values (1) := (Locus => (Token => Make_Token ("bank")), Measure => (Token => Make_Token ("jpy")));
         Coords.Values (2) := (Locus => (Token => Make_Token ("wallet")), Measure => (Token => Make_Token ("jpy")));
         Coords.Values (3) := (Locus => (Token => Make_Token ("bank")), Measure => (Token => Make_Token ("jpy")));
         Coords.Values (4) := (Locus => (Token => Make_Token ("yucho")), Measure => (Token => Make_Token ("jpy")));

         --  End_Exclusive: 2026-01-05 (day 4)
         declare
            End_D : constant Date_Type := (Year => 2026, Month => 1, Day => 5);
            Res   : constant Balance_Effects_Result :=
              Calculate_Balance_Effects (Life, Events, Coords, End_D);
         begin
            Assert (Res.Status = Status_Ok, "Loam fixture calculation succeeds");
            Assert_Equal_Int (3, Long_Long_Integer (Res.Effects.Count), "Normalized to 3 projected balance rows");

            --  Row 1: bank -55
            Assert (Equal_Token (Res.Effects.Effects (1).Coordinate.Locus.Token, Make_Token ("bank")),
              "Row 1 is bank");
            Assert_Equal_Int (-55, Long_Long_Integer (Res.Effects.Effects (1).Quantity),
              "Row 1 bank effect is exact -55");

            --  Row 2: wallet 25
            Assert (Equal_Token (Res.Effects.Effects (2).Coordinate.Locus.Token, Make_Token ("wallet")),
              "Row 2 is wallet");
            Assert_Equal_Int (25, Long_Long_Integer (Res.Effects.Effects (2).Quantity),
              "Row 2 wallet effect is exact 25");

            --  Row 3: yucho 0
            Assert (Equal_Token (Res.Effects.Effects (3).Coordinate.Locus.Token, Make_Token ("yucho")),
              "Row 3 is yucho");
            Assert_Equal_Int (0, Long_Long_Integer (Res.Effects.Effects (3).Quantity),
              "Row 3 yucho effect is exact 0");
         end;

         -- ======================================================================
         --  4. Day Evidence Tests
         -- ======================================================================
         declare
            Due_Res : constant Day_Evidence_Result :=
              Query_Day_Evidence (Life, Events, (2026, 1, 3));
            Unk_Res : constant Day_Evidence_Result :=
              Query_Day_Evidence (Life, Events, (2026, 1, 2));
         begin
            Assert (Due_Res.Kind = Evidence_Due, "Day with scheduled-payment is Evidence_Due");
            Assert_Equal_Int (1, Long_Long_Integer (Due_Res.Count), "Exact 1 open occurrence on 2026-01-03");

            Assert (Unk_Res.Kind = Evidence_Unknown, "Day with no scheduled is Evidence_Unknown");
            Assert_Equal_Int (0, Long_Long_Integer (Unk_Res.Count), "0 occurrences on 2026-01-02");
         end;

         -- ======================================================================
         --  5. Scheduled Suppression Comparison Tests
         -- ======================================================================
         declare
            End_D       : constant Date_Type := (Year => 2026, Month => 1, Day => 5);
            Payment_Id  : constant Scheduled_Id := (Token => Make_Token ("scheduled-payment"));
            Retired_Id  : constant Scheduled_Id := (Token => Make_Token ("scheduled-retired"));
            Unknown_Id  : constant Scheduled_Id := (Token => Make_Token ("scheduled-ghost"));

            Comp_Res : constant Suppression_Comparison_Result :=
              Compare_Suppression (Life, Events, Coords, End_D, Payment_Id);
         begin
            Assert (Comp_Res.Status = Status_Ok, "Suppression comparison of open payment succeeds");
            --  Baseline: bank -55, wallet 25, yucho 0
            Assert_Equal_Int (-55, Long_Long_Integer (Comp_Res.Baseline.Effects (1).Quantity),
              "Baseline bank effect is -55");
            Assert_Equal_Int (25, Long_Long_Integer (Comp_Res.Baseline.Effects (2).Quantity),
              "Baseline wallet effect is 25");

            --  Projected without payment (-30 bank, +30 rent):
            --  bank becomes -55 - (-30) = -25
            Assert_Equal_Int (-25, Long_Long_Integer (Comp_Res.Projected.Effects (1).Quantity),
              "Projected bank effect suppressing payment is -25");
            Assert_Equal_Int (25, Long_Long_Integer (Comp_Res.Projected.Effects (2).Quantity),
              "Projected wallet effect suppressing payment remains 25");

            --  Target not open (already retired)
            declare
               Not_Open_Res : constant Suppression_Comparison_Result :=
                 Compare_Suppression (Life, Events, Coords, End_D, Retired_Id);
            begin
               Assert (Not_Open_Res.Status = Status_Target_Not_Open,
                 "Suppression on already-retired scheduled fails closed with Status_Target_Not_Open");
            end;

            --  Target not open (unknown id)
            declare
               Unknown_Res : constant Suppression_Comparison_Result :=
                 Compare_Suppression (Life, Events, Coords, End_D, Unknown_Id);
            begin
               Assert (Unknown_Res.Status = Status_Target_Not_Open,
                 "Suppression on unknown scheduled fails closed with Status_Target_Not_Open");
            end;
         end;
      end;

      -- =========================================================================
      --  6. Replacement Publisher Sandbox Tests
      -- =========================================================================
      if not Real_Data_Available then
         Ada.Text_IO.Put_Line ("    [SKIP] Real scheduled data not present for publisher sandbox test");
         return;
      end if;

      Setup_Sandbox;

      --  Publish valid replacement of scheduled-3 (originally 2026-09-15 smbc -> gpt-plus 3000)
      declare
         Draft : constant Replacement_Draft :=
           Make_Two_Party_Draft
             (Source      => "scheduled-3",
              From_Locus  => "smbc",
              To_Locus    => "gpt-plus",
              Amount      => 3500,
              Valid_On    => (2026, 9, 20),
              Measure_Str => "jpy");
         Receipt : constant Replacement_Receipt :=
           Publish_Replacement (Sandbox_Sched, Sandbox_Auth, Draft);
      begin
         Assert (Receipt.Success, "Replacement publication of scheduled-3 succeeds");
         Assert (Equal_Token (Receipt.Source.Token, Make_Token ("scheduled-3")),
           "Receipt source matches scheduled-3");
         Assert (Receipt.Replacement.Token.Length > 0,
           "Receipt allocated fresh replacement id");

         --  Verify on disk
         declare
            Reload_Res : constant Read_Scheduled_Result := Read_Scheduled_File (Sandbox_Sched);
            Repl_Id    : constant Scheduled_Id := Receipt.Replacement;
         begin
            Assert (Reload_Res.Success, "Reloading scheduled.loam after replacement succeeds");
            Assert_Equal_Int (1, Long_Long_Integer (Reload_Res.Lifecycle.Repl_Count),
              "Exact 1 replacement relation stored");
            Assert (Equal_Token (Reload_Res.Lifecycle.Repl_Items (1).Original.Token, Make_Token ("scheduled-3")),
              "Stored replacement original is scheduled-3");
            Assert (Equal_Token (Reload_Res.Lifecycle.Repl_Items (1).Replaced_By.Token, Repl_Id.Token),
              "Stored replacement target matches allocated id");

            --  Check current-open state:
            --  scheduled-3 should NO LONGER be current open
            --  Repl_Id SHOULD be current open
            declare
               Old_Lookup : constant Lookup_Result := Find_Occurrence (Reload_Res.Lifecycle, (Token => Make_Token ("scheduled-3")));
               New_Lookup : constant Lookup_Result := Find_Occurrence (Reload_Res.Lifecycle, Repl_Id);
            begin
               Assert (Old_Lookup.Found, "Old occurrence scheduled-3 still exists in append-only history");
               Assert (New_Lookup.Found, "New replacement occurrence found in history");
               Assert_Equal_Int (3500, Long_Long_Integer (New_Lookup.Item.Changes.Values (2).Amount),
                 "New occurrence amount is 3500");
               Assert (not Is_Current_Open (Reload_Res.Lifecycle, (Token => Make_Token ("scheduled-3"))),
                 "Replaced scheduled-3 is no longer current-open");
               Assert (Is_Current_Open (Reload_Res.Lifecycle, Repl_Id),
                 "New replacement occurrence is current-open");
            end;
         end;

         --  Negative test 1: Cannot replace already replaced scheduled-3
         declare
            Stale_Draft : constant Replacement_Draft :=
              Make_Two_Party_Draft
                (Source      => "scheduled-3",
                From_Locus  => "smbc",
                To_Locus    => "gpt-plus",
                Amount      => 4000,
                Valid_On    => (2026, 9, 21));
            Stale_Rec : constant Replacement_Receipt :=
              Publish_Replacement (Sandbox_Sched, Sandbox_Auth, Stale_Draft);
         begin
            Assert (not Stale_Rec.Success, "Re-replacing superseded scheduled-3 fails closed");
         end;

         --  Negative test 2: Impossible calendar date 2026-02-29
         declare
            Bad_Date_Draft : constant Replacement_Draft :=
              Make_Two_Party_Draft
                (Source      => Receipt.Replacement.Token.Value (1 .. Receipt.Replacement.Token.Length),
                 From_Locus  => "smbc",
                 To_Locus    => "gpt-plus",
                 Amount      => 3500,
                 Valid_On    => (2026, 2, 29));
            Bad_Rec : constant Replacement_Receipt :=
              Publish_Replacement (Sandbox_Sched, Sandbox_Auth, Bad_Date_Draft);
         begin
            Assert (not Bad_Rec.Success, "Impossible date 2026-02-29 refused fail-closed");
         end;

         --  Negative test 3: Unadmitted locus
         declare
            Bad_Loc_Draft : constant Replacement_Draft :=
              Make_Two_Party_Draft
                (Source      => Receipt.Replacement.Token.Value (1 .. Receipt.Replacement.Token.Length),
                 From_Locus  => "unadmitted_locus_xyz",
                 To_Locus    => "gpt-plus",
                 Amount      => 3500,
                 Valid_On    => (2026, 9, 25));
            Bad_Rec : constant Replacement_Receipt :=
              Publish_Replacement (Sandbox_Sched, Sandbox_Auth, Bad_Loc_Draft);
         begin
            Assert (not Bad_Rec.Success, "Unadmitted locus in replacement draft refused fail-closed");
         end;
      end;
   end Run;

end Test_Scheduled_Balance;
