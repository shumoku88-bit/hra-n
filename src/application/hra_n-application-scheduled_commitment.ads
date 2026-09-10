-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Scheduled_Commitment
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Scheduled_Routing; use HRA_N.Core.Scheduled_Routing;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;

package HRA_N.Application.Scheduled_Commitment is
   Max_Managed_Purposes : constant := 32;
   type Managed_Row is record
      Purpose : Token_Text;
      Quantity : Quanta_Type := Zero_Quanta;
   end record;
   type Managed_Array is array (1 .. Max_Managed_Purposes) of Managed_Row;

   type Commitment_Report is record
      Resolved               : Boolean := True;
      Managed_Count          : Natural := 0;
      Managed                : Managed_Array := [others =>
        (Purpose => (Length => 0, Value => [others => ' ']), Quantity => 0)];
      Managed_Total          : Quanta_Type := 0;
      Unmanaged              : Quanta_Type := 0;
      Unrouted               : Quanta_Type := 0;
      Unresolved_Eligibility : Quanta_Type := 0;
      Open_Occurrences       : Natural := 0;
      Selected_Coordinates   : Natural := 0;
   end record;

   procedure Project
     (Lifecycle    : Scheduled_Lifecycle;
      Events       : Event_Vectors.Vector;
      Roles        : Role_Map;
      Routing      : Routing_History;
      Measure      : Measure_Id;
      Observed_At  : Date_Type;
      End_Exclusive: Date_Type;
      Report       : out Commitment_Report);
end HRA_N.Application.Scheduled_Commitment;
