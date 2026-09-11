-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: Test_HRA_Storage
-------------------------------------------------------------------------------

with Test_Support;                            use Test_Support;
with Ada.Text_IO;
with HRA_N.Core.Attention;                   use HRA_N.Core.Attention;
with HRA_N.Core.Capacity;                      use HRA_N.Core.Capacity;
with HRA_N.Core.Types;                         use HRA_N.Core.Types;
with HRA_N.Core.Event;                         use HRA_N.Core.Event;
with HRA_N.Core.Validity;                      use HRA_N.Core.Validity;
with HRA_N.Core.Description;                   use HRA_N.Core.Description;
with HRA_N.Core.Coverage;                      use HRA_N.Core.Coverage;
with HRA_N.Core.Scheduled;                     use HRA_N.Core.Scheduled;
with HRA_N.Storage.Journal_Reader;             use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader;              use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader;   use HRA_N.Storage.Scheduled_Journal_Reader;
with Ada.Directories;
with HRA_N.Storage.Scheduled_Journal_Writer;

package body Test_HRA_Storage is

   procedure Run is
      HRA_Data_Dir : constant String := "/Users/user/Projects/moko/hra-data";
      JPY          : constant Measure_Id := (Token => Make_Token ("jpy"));
   begin
      -- 1. Test Journal_Reader
      declare
         Non_Existent : constant Journal_Result := Read_Journal_File ("/non/existent/journal.hra");
      begin
         Assert (not Non_Existent.Success, "Non-existent journal.hra fails closed");
      end;

      declare
         J_Res : constant Journal_Result := Read_Journal_File (HRA_Data_Dir & "/journal.hra");
      begin
         Assert (J_Res.Success, "Real journal.hra loads successfully");
         Assert_Equal_Int (588, Long_Long_Integer (J_Res.Events.Length), "Loaded exact count of 588 events");
         Assert_Equal_Int (588, Long_Long_Integer (Entry_Count (J_Res.Validities)), "Loaded exact count of 588 validity facts");
         Assert_Equal_Int (588, Long_Long_Integer (Entry_Count (J_Res.Descriptions)), "Loaded exact count of 588 description facts");

         -- Verify exact balances from journal
         declare
            Cash_Bal   : Long_Long_Integer := 0;
            PayPay_Bal : Long_Long_Integer := 0;
            Smbc_Bal   : Long_Long_Integer := 0;
            Yucho_Bal  : Long_Long_Integer := 0;
            AllC_Bal   : Long_Long_Integer := 0;

            Cash_Loc   : constant Locus_Id := (Token => Make_Token ("cash"));
            PayPay_Loc : constant Locus_Id := (Token => Make_Token ("paypay"));
            Smbc_Loc   : constant Locus_Id := (Token => Make_Token ("smbc"));
            Yucho_Loc  : constant Locus_Id := (Token => Make_Token ("yucho"));
            AllC_Loc   : constant Locus_Id := (Token => Make_Token ("all-country"));
         begin
            for Ev of J_Res.Events loop
               Cash_Bal   := Cash_Bal   + Quantity_At (Ev, Cash_Loc, JPY);
               PayPay_Bal := PayPay_Bal + Quantity_At (Ev, PayPay_Loc, JPY);
               Smbc_Bal   := Smbc_Bal   + Quantity_At (Ev, Smbc_Loc, JPY);
               Yucho_Bal  := Yucho_Bal  + Quantity_At (Ev, Yucho_Loc, JPY);
               AllC_Bal   := AllC_Bal   + Quantity_At (Ev, AllC_Loc, JPY);
            end loop;

            Assert_Equal_Int (909, Cash_Bal, "Cash balance matches exactly: 909 jpy");
            Assert_Equal_Int (714, PayPay_Bal, "PayPay balance matches exactly: 714 jpy");
            Assert_Equal_Int (72179, Smbc_Bal, "SMBC balance matches exactly: 72179 jpy");
            Assert_Equal_Int (5000, Yucho_Bal, "Yucho balance matches exactly: 5000 jpy");
            Assert_Equal_Int (5600, AllC_Bal, "All-Country balance matches exactly: 5600 jpy");
         end;
      end;

      -- 2. Test Policy_Reader
      declare
         Non_Existent : constant Policy_Result := Read_Policy_File ("/non/existent/policy.hra");
      begin
         Assert (not Non_Existent.Success, "Non-existent policy.hra fails closed");
      end;

      declare
         P_Res : constant Policy_Result := Read_Policy_File (HRA_Data_Dir & "/policy.hra");
      begin
         Assert (P_Res.Success, "Real policy.hra loads successfully");
         Assert_Equal_Int (40, Long_Long_Integer (P_Res.Roles.Count), "Loaded 40 accounting roles");
         Assert_Equal_Int (5, Long_Long_Integer (Coordinate_Count (P_Res.Coverage)), "Loaded 5 zero-origin coverage coordinates");
         Assert_Equal_Int (6, Long_Long_Integer (P_Res.Capacities.Movement_Count), "Loaded 6 capacity envelope movements");
         Assert_Equal_Int (6, Long_Long_Integer (P_Res.Capacities.Effective_Count), "Loaded 6 capacity effective facts");
         Assert (Equal_Token
                   (P_Res.Capacities.Movements (1).Id, Make_Token ("cap0001")),
                 "First capacity movement carries a stable identity");
         Assert (Has_Effective_Date
                   (P_Res.Capacities,
                    P_Res.Capacities.Movements (1).Id),
                 "Backfilled effective evidence resolves");
         Assert (Effective_Evidence_Complete (P_Res.Capacities),
                 "Real capacity evidence is complete");
         Assert_Equal_Int (22, Long_Long_Integer (P_Res.Routing.Count), "Loaded 22 actual routing rules");
      end;

      -- 3. Test Scheduled_Journal_Reader
      declare
         Non_Existent : constant Scheduled_Journal_Result := Read_Scheduled_Journal_File ("/non/existent/scheduled.hra");
      begin
         Assert (not Non_Existent.Success, "Non-existent scheduled.hra fails closed");
      end;

      declare
         S_Res : constant Scheduled_Journal_Result := Read_Scheduled_Journal_File (HRA_Data_Dir & "/scheduled.hra");
         Open_Count : Natural := 0;
      begin
         Assert (S_Res.Success, "Real scheduled.hra loads successfully");
         Assert_Equal_Int (13, Long_Long_Integer (S_Res.Lifecycle.Sched_Count), "Loaded 13 scheduled obligations");
         Assert_Equal_Int (2, Long_Long_Integer (S_Res.Lifecycle.Comp_Count), "Loaded 2 completions");

         for I in 1 .. S_Res.Lifecycle.Sched_Count loop
            if Is_Current_Open (S_Res.Lifecycle, S_Res.Lifecycle.Sched_Items (I).Id) then
               Open_Count := Open_Count + 1;
            end if;
         end loop;

         Assert_Equal_Int (11, Long_Long_Integer (Open_Count), "Exact 11 active open scheduled obligations");
      end;

      -- 4. Test Journal_Writer (roundtrip)
      declare
         Tmp_Journal : constant String := "/tmp/test_journal_writer.hra";
         Effs        : Effect_List;
         App_Res     : HRA_N.Storage.Journal_Writer.Append_Result;
      begin
         if Ada.Directories.Exists (Tmp_Journal) then
            Ada.Directories.Delete_File (Tmp_Journal);
         end if;
         Effs.Count := 2;
         Effs.Values (1) :=
           (Key     => (Token => Make_Token ("f1")),
            Locus   => (Token => Make_Token ("smbc")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => -1000));
         Effs.Values (2) :=
           (Key     => (Token => Make_Token ("f2")),
            Locus   => (Token => Make_Token ("food")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => 1000));

         App_Res := HRA_N.Storage.Journal_Writer.Append_Transaction
           (Journal_Path => Tmp_Journal,
            Tx_Id        => "tx-test-99",
            Valid_On     => Make_Date (2026, 9, 10),
            Effects      => Effs,
            Purpose      => "food",
            Description  => "Roundtrip Test Note");

         Assert (App_Res.Success, "Append_Transaction succeeds");

         declare
            Read_Back : constant Journal_Result := Read_Journal_File (Tmp_Journal);
         begin
            Assert (Read_Back.Success, "Read back appended journal succeeds");
            Assert_Equal_Int (1, Long_Long_Integer (Read_Back.Events.Length), "1 event read back");
            Assert_Equal_Int (1, Long_Long_Integer (Entry_Count (Read_Back.Validities)), "1 validity fact read back");
            Assert_Equal_Int (1, Long_Long_Integer (Entry_Count (Read_Back.Descriptions)), "1 description fact read back");
         end;
      end;

      -- 5. Test Scheduled_Journal_Writer (roundtrip)
      declare
         S_Res : constant Scheduled_Journal_Result := Read_Scheduled_Journal_File (HRA_Data_Dir & "/scheduled.hra");
         Tmp_Sched : constant String := "/tmp/test_scheduled_writer.hra";
         W_Res     : HRA_N.Storage.Scheduled_Journal_Writer.Write_Result;
      begin
         Assert (S_Res.Success, "Source scheduled.hra loaded for writer test");
         W_Res := HRA_N.Storage.Scheduled_Journal_Writer.Write_Scheduled_Journal_File
           (Path      => Tmp_Sched,
            Lifecycle => S_Res.Lifecycle);
         Assert (W_Res.Success, "Write_Scheduled_Journal_File succeeds");

         declare
            Read_Back : constant Scheduled_Journal_Result := Read_Scheduled_Journal_File (Tmp_Sched);
         begin
            Assert (Read_Back.Success, "Read back rewritten scheduled.hra succeeds");
            Assert_Equal_Int (13, Long_Long_Integer (Read_Back.Lifecycle.Sched_Count), "All 13 scheduled items preserved");
            Assert_Equal_Int (2, Long_Long_Integer (Read_Back.Lifecycle.Comp_Count), "All 2 completions preserved");
         end;
      end;

      --  6. Test capacity wire admission (TRANSFER, REBALANCE, EFFECTIVE)
      declare
         Tmp_Policy : constant String := "/tmp/test_capacity_wire.hra";

         procedure Write_Policy (Content : String) is
            File : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Tmp_Policy);
            Ada.Text_IO.Put (File, Content);
            Ada.Text_IO.Close (File);
         end Write_Policy;
      begin
         Write_Policy
           ("CAPACITY food 5000 jpy" & ASCII.LF
            & "EFFECTIVE cap0001 2026-09-01" & ASCII.LF
            & "TRANSFER unallocated misc 2000 jpy 2026-09-02" & ASCII.LF
            & "REBALANCE jpy 2026-09-03 food:-1000 misc:800 unallocated:200" & ASCII.LF);
         declare
            R : constant Policy_Result := Read_Policy_File (Tmp_Policy);
         begin
            Assert (R.Success, "Capacity wire with backfilled effective stays admitted");
            Assert_Equal_Int (3, Long_Long_Integer (R.Capacities.Movement_Count),
                              "Three capacity movements retained");
            Assert (Effective_Evidence_Complete (R.Capacities),
                    "Inline and backfilled effectives complete the evidence");
            Assert (All_Movements_Conserved (R.Capacities),
                    "All wire movements conserve");
            Assert (Entitlement_At
                      (R.Capacities, Make_Unallocated_Coordinate,
                       Make_Token ("jpy")) = -6_800,
                    "Unallocated entitlement nets funding, transfer, and rebalance");
         end;

         Write_Policy
           ("CAPACITY food 5000 jpy" & ASCII.LF
            & "EFFECTIVE cap0001 2026-09-01" & ASCII.LF
            & "EFFECTIVE cap0001 2026-09-02" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Duplicate effective coordinate fails closed");

         Write_Policy ("EFFECTIVE cap0007 2026-09-01" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Dangling effective reference fails closed");

         Write_Policy
           ("TRANSFER unallocated misc 2000 jpy 2026-09-02" & ASCII.LF
            & "EFFECTIVE cap0001 2026-09-03" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Second coordinate for an inline-dated movement fails closed");

         Write_Policy
           ("REBALANCE jpy 2026-09-03 food:-1000 misc:800 unallocated:100" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Unbalanced rebalance fails closed");

         Write_Policy
           ("REBALANCE jpy 2026-09-03 food:-1000 food:1000" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Rebalance repeating a coordinate fails closed");

         Write_Policy
           ("REBALANCE jpy 2026-09-03 food:-1000 unallocated:0 misc:1000" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Rebalance with a zero change fails closed");

         Write_Policy
           ("TRANSFER food food 1000 jpy 2026-09-03" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Transfer with identical endpoints fails closed");

         Write_Policy
           ("CAPACITY food 100 euro" & ASCII.LF);
         declare
            R : constant Policy_Result := Read_Policy_File (Tmp_Policy);
         begin
            Assert (R.Success, "Non-jpy capacity remains readable compat input");
            Assert (Equal_Token
                      (R.Capacities.Movements (1).Currency, Make_Token ("euro")),
                    "Currency is retained exactly, never silently defaulted");
         end;

         --  7. Test attention wire admission (ATTENTION, ATTENTION-CLOSE)
         Write_Policy
           ("ATTENTION att0001 ""Renew insurance"" due:2026-10-01" & ASCII.LF
            & "ATTENTION att0002 ""Deep clean"" nodue" & ASCII.LF
            & "ATTENTION att0003 ""Mystery noise"" due-unknown" & ASCII.LF
            & "ATTENTION-CLOSE att0001 resolved 2026-09-20" & ASCII.LF);
         declare
            R : constant Policy_Result := Read_Policy_File (Tmp_Policy);
         begin
            Assert (R.Success, "Attention wire stays admitted");
            Assert_Equal_Int (3, Long_Long_Integer (R.Attention.Item_Count),
                              "Three attention items retained");
            Assert_Equal_Int (2, Long_Long_Integer (Open_Count (R.Attention)),
                              "One closure leaves two open items");
            Assert (not Is_Open (R.Attention, Make_Token ("att0001")),
                    "Closed item is not open");
            Assert (Is_Open (R.Attention, Make_Token ("att0003")),
                    "Undated item stays open");
         end;

         Write_Policy
           ("ATTENTION att0001 ""First"" nodue" & ASCII.LF
            & "ATTENTION att0001 ""Second"" nodue" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Duplicate attention identity fails closed");

         Write_Policy ("ATTENTION-CLOSE att0009 resolved 2026-09-20" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Dangling attention closure fails closed");

         Write_Policy
           ("ATTENTION att0001 ""First"" nodue" & ASCII.LF
            & "ATTENTION-CLOSE att0001 resolved 2026-09-20" & ASCII.LF
            & "ATTENTION-CLOSE att0001 dropped 2026-09-21" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Second closure of one item fails closed");

         Write_Policy
           ("ATTENTION att0001 ""No due word"" 2026-10-01" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Attention without an explicit due word fails closed");

         Write_Policy
           ("ATTENTION att0001 ""Bad kind"" someday" & ASCII.LF);
         Assert (not Read_Policy_File (Tmp_Policy).Success,
                 "Attention with an unknown due word fails closed");
      end;

   end Run;

end Test_HRA_Storage;
