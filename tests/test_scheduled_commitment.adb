with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Routing; use HRA_N.Core.Scheduled_Routing;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Scheduled_Reader; use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Scheduled_Routing;
with HRA_N.Storage.Accounting_Role_Reader;
with HRA_N.Application.Scheduled_Commitment;
use HRA_N.Application.Scheduled_Commitment;
with Test_Support; use Test_Support;

package body Test_Scheduled_Commitment is
   function Occurrence
     (Name, Positive_Locus : String; Amount : Quanta_Type;
      Day : Date_Type) return Scheduled_Occurrence
   is
      Changes : Change_List;
   begin
      Changes.Count := 2;
      Changes.Values (1) :=
        (Locus => (Token => Make_Token ("cash")), Amount => -Amount);
      Changes.Values (2) :=
        (Locus => (Token => Make_Token (Positive_Locus)), Amount => Amount);
      return (Id => (Token => Make_Token (Name)), Expected_Day => Day,
              Measure => (Token => Make_Token ("jpy")), Changes => Changes);
   end Occurrence;

   procedure Run is
      Lifecycle : Scheduled_Lifecycle;
      Events : Event_Vectors.Vector;
      Roles : Role_Map;
      Routing : Routing_History;
      Report : Commitment_Report;
   begin
      Lifecycle.Sched_Count := 3;
      Lifecycle.Sched_Items (1) :=
        Occurrence ("s1", "rent", 100, Make_Date (2026, 9, 15));
      Lifecycle.Sched_Items (2) :=
        Occurrence ("s2", "bank", 200, Make_Date (2026, 9, 16));
      Lifecycle.Sched_Items (3) :=
        Occurrence ("s3", "mystery", 50, Make_Date (2026, 9, 17));
      Roles.Count := 2;
      Roles.Entries (1) :=
        (Locus => (Token => Make_Token ("rent")), Role => Role_Expense);
      Roles.Entries (2) :=
        (Locus => (Token => Make_Token ("bank")), Role => Role_Asset);
      Routing.Count := 1;
      Routing.Entries (1) :=
        (Scheduled => (Token => Make_Token ("s1")),
         Locus => (Token => Make_Token ("rent")),
         Effective_On => Make_Date (2026, 9, 10), Managed => True,
         Purpose => Make_Token ("fixed"));

      Project
        (Lifecycle, Events, Roles, Routing, (Token => Make_Token ("jpy")),
         Make_Date (2026, 9, 10), Make_Date (2026, 10, 1), Report);
      Assert (Report.Resolved, "Scheduled commitment projection resolves");
      Assert (Report.Managed_Total = 100 and then Report.Managed_Count = 1,
              "Explicit route creates managed Purpose commitment");
      Assert (Report.Unrouted = 0,
              "Unrouted positive Asset is resolved non-pressure");
      Assert (Report.Unresolved_Eligibility = 50,
              "Missing AccountingRole remains unresolved eligibility");
      Assert (Report.Selected_Coordinates = 3,
              "Each positive ScheduledId/Locus coordinate selected once");

      Routing.Entries (1).Managed := False;
      Routing.Entries (1).Purpose := Make_Token ("");
      Project
        (Lifecycle, Events, Roles, Routing, (Token => Make_Token ("jpy")),
         Make_Date (2026, 9, 10), Make_Date (2026, 10, 1), Report);
      Assert (Report.Unmanaged = 100 and then Report.Managed_Total = 0,
              "Explicit unmanaged route remains visible outside managed pressure");

      Routing.Count := 0;
      Project
        (Lifecycle, Events, Roles, Routing, (Token => Make_Token ("jpy")),
         Make_Date (2026, 9, 10), Make_Date (2026, 9, 16), Report);
      Assert (Report.Unrouted = 100,
              "Unrouted Expense exerts fallback pressure");
      Assert (Report.Selected_Coordinates = 1,
              "End-exclusive horizon excludes boundary occurrence");

      Project
        (Lifecycle, Events, Roles, Routing, (Token => Make_Token ("jpy")),
         Make_Date (2026, 10, 1), Make_Date (2026, 9, 1), Report);
      Assert (not Report.Resolved, "Invalid commitment horizon fails closed");

      if Real_Data_Available then
         declare
            Man : constant Read_Manifest_Result := Read_Manifest_File
              (Real_Data_Dir & "/movement-authority/CURRENT");
            E_Item : constant Manifest_Item := Man.Manifest (Family_Event);
            Real_Events : constant Read_Result := Read_Event_Memory_File
              (Real_Data_Dir & "/movement-authority/" &
               E_Item.Rel_Path (1 .. E_Item.Path_Len));
            Real_Scheduled : constant Read_Scheduled_Result := Read_Scheduled_File
              (Real_Data_Dir & "/scheduled.loam");
            Real_Routing : constant HRA_N.Storage.Scheduled_Routing.Read_Result :=
              HRA_N.Storage.Scheduled_Routing.Read_File
                (Real_Data_Dir & "/scheduled-routing.loam");
            Real_Roles : constant HRA_N.Storage.Accounting_Role_Reader.Read_Result :=
              HRA_N.Storage.Accounting_Role_Reader.Read_Accounting_Role_File
                (Real_Data_Dir & "/accounting-role.loam");
         begin
            Project
              (Real_Scheduled.Lifecycle, Real_Events.Events, Real_Roles.Map,
               Real_Routing.History, (Token => Make_Token ("jpy")),
               Make_Date (2026, 9, 10), Make_Date (2026, 10, 16), Report);
            Assert (Report.Resolved, "Production Scheduled commitment resolves");
            Assert (Report.Open_Occurrences = 11,
                    "Production current-open Scheduled count is exact");
            Assert (Report.Managed_Total = 12_360,
                    "Production managed commitment is exact");
            Assert (Report.Unrouted = 95_310,
                    "Production AccountingRole fallback pressure is exact");
            Assert (Report.Unresolved_Eligibility = 0,
                    "Production commitment eligibility frontier is complete");
         end;
      end if;
   end Run;
end Test_Scheduled_Commitment;
