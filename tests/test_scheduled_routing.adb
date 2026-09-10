with Ada.Directories;
with GNAT.OS_Lib;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Routing; use HRA_N.Core.Scheduled_Routing;
with HRA_N.Storage.Scheduled_Routing;
with HRA_N.Application.Scheduled_Routing_Publisher;
use HRA_N.Application.Scheduled_Routing_Publisher;
with Test_Support; use Test_Support;

package body Test_Scheduled_Routing is
   Sandbox : constant String := "/tmp/hra_n_test_scheduled_routing";

   procedure Copy_File (Source, Target : String) is
      Success : Boolean;
      Args : GNAT.OS_Lib.Argument_List (1 .. 2);
   begin
      Args (1) := new String'(Source);
      Args (2) := new String'(Target);
      GNAT.OS_Lib.Spawn ("/bin/cp", Args, Success);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
   end Copy_File;

   procedure Run is
      History : Routing_History;
      Current : Route_Result;
      Sched : constant Scheduled_Id := (Token => Make_Token ("scheduled-1"));
      Wifi : constant Locus_Id := (Token => Make_Token ("wifi"));
   begin
      History.Count := 3;
      History.Entries (1) :=
        (Scheduled => Sched, Locus => Wifi, Effective_On => Make_Date (2026, 1, 1),
         Managed => True, Purpose => Make_Token ("fixed"));
      History.Entries (2) :=
        (Scheduled => Sched, Locus => Wifi, Effective_On => Make_Date (2026, 2, 1),
         Managed => False, Purpose => Make_Token (""));
      History.Entries (3) :=
        (Scheduled => Sched, Locus => Wifi, Effective_On => Make_Date (2026, 3, 1),
         Managed => True, Purpose => Make_Token ("new-fixed"));
      Assert (Coordinates_Are_Unique (History), "Scheduled route coordinates are unique");
      Find_Current_Route (History, Sched, Wifi, Make_Date (2026, 1, 15), Current);
      Assert (Current.State = Route_Managed
              and then Equal_Token (Current.Purpose, Make_Token ("fixed")),
              "Latest visible managed route is selected independent of row order");
      Find_Current_Route (History, Sched, Wifi, Make_Date (2026, 2, 15), Current);
      Assert (Current.State = Route_Unmanaged,
              "Explicit unmanaged evidence overrides earlier managed route");
      Find_Current_Route (History, Sched, Wifi, Make_Date (2025, 12, 31), Current);
      Assert (Current.State = Route_Unknown,
              "No visible routing evidence remains unknown");
      declare
         Encoded : constant String :=
           HRA_N.Storage.Scheduled_Routing.Encode (History);
         Header : constant String := "LOAM-SCHEDULED-ROUTING" & ASCII.HT & "1" & ASCII.LF;
      begin
         Assert (Encoded'Length > Header'Length
                 and then Encoded (Encoded'First .. Encoded'First + Header'Length - 1) = Header,
                 "Scheduled routing encoder emits canonical Loam v1 header");
      end;

      if Real_Data_Available then
         declare
            Real : constant HRA_N.Storage.Scheduled_Routing.Read_Result :=
              HRA_N.Storage.Scheduled_Routing.Read_File
                (Real_Data_Dir & "/scheduled-routing.loam");
         begin
            Assert (Real.Success, "Production scheduled-routing.loam parses");
            Assert (Real.History.Count = 7, "Production routing holds seven assertions");
            Assert (Coordinates_Are_Unique (Real.History),
                    "Production Scheduled route coordinates are unique");
            Find_Current_Route
              (Real.History, Sched, Wifi, Make_Date (2026, 9, 10), Current);
            Assert (Current.State = Route_Managed and then Current.Purpose.Length = 15,
                    "Production scheduled-1/wifi route resolves managed Purpose");
         end;

         if Ada.Directories.Exists (Sandbox) then
            Ada.Directories.Delete_Tree (Sandbox);
         end if;
         Ada.Directories.Create_Path (Sandbox);
         Copy_File (Real_Data_Dir & "/scheduled.loam", Sandbox & "/scheduled.loam");
         Copy_File
           (Real_Data_Dir & "/scheduled-routing.loam", Sandbox & "/routing.loam");
         declare
            Added : constant Publish_Result := Publish
              (Routing_Path => Sandbox & "/routing.loam",
               Scheduled_Path => Sandbox & "/scheduled.loam",
               Scheduled => Sched, Locus => Wifi,
               Effective_On => Make_Date (2026, 9, 11),
               Target => Target_Unmanaged);
         begin
            Assert (Added.Success, "Scheduled unmanaged route publication succeeds");
         end;
         declare
            Duplicate : constant Publish_Result := Publish
              (Routing_Path => Sandbox & "/routing.loam",
               Scheduled_Path => Sandbox & "/scheduled.loam",
               Scheduled => Sched, Locus => Wifi,
               Effective_On => Make_Date (2026, 9, 11),
               Target => Target_Managed, Purpose => Make_Token ("fixed"));
         begin
            Assert (not Duplicate.Success,
                    "Duplicate Scheduled subject/effective coordinate is rejected");
         end;
         declare
            Missing_Locus : constant Publish_Result := Publish
              (Routing_Path => Sandbox & "/routing.loam",
               Scheduled_Path => Sandbox & "/scheduled.loam",
               Scheduled => Sched, Locus => (Token => Make_Token ("not-in-plan")),
               Effective_On => Make_Date (2026, 9, 12),
               Target => Target_Unmanaged);
         begin
            Assert (not Missing_Locus.Success,
                    "Route publisher rejects Locus absent from Scheduled occurrence");
         end;
         declare
            Updated : constant HRA_N.Storage.Scheduled_Routing.Read_Result :=
              HRA_N.Storage.Scheduled_Routing.Read_File (Sandbox & "/routing.loam");
         begin
            Assert (Updated.Success and then Updated.History.Count = 8,
                    "Published Scheduled route persists as eighth assertion");
            Find_Current_Route
              (Updated.History, Sched, Wifi, Make_Date (2026, 9, 12), Current);
            Assert (Current.State = Route_Unmanaged,
                    "Published unmanaged route becomes current projection");
         end;
      end if;
   end Run;
end Test_Scheduled_Routing;
