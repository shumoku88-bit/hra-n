-------------------------------------------------------------------------------
--  HRA-N: shared Scheduled record detail query
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Application.Scheduled_Query;

package HRA_N.Application.Scheduled_Detail_Query is

   type Scheduled_Change_View is record
      Locus  : Token_Text;
      Amount : Quanta_Type := 0;
   end record;

   Empty_Change_View : constant Scheduled_Change_View :=
     (Locus  => (Length => 0, Value => [others => ' ']),
      Amount => 0);

   type Scheduled_Change_View_Array is array (Change_Index_Type) of Scheduled_Change_View;

   type Scheduled_Detail_View is record
      Status           : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot         : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Id               : Token_Text;
      Expected_Day     : Date_Type;
      Measure          : Token_Text;
      Lifecycle_Status : Scheduled_Query.Scheduled_Status_Kind :=
        Scheduled_Query.Status_Open;
      Has_Terminal_Ref : Boolean := False;
      Terminal_Ref     : Token_Text;
      Change_Count     : Change_Count_Type := 0;
      Changes          : Scheduled_Change_View_Array := [others => Empty_Change_View];
      Diagnostic       : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len   : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  Re-read the scheduled journal and resolve one visible identity.
   --  A missing or unadmitted identity is rejected rather than assumed.
   function Execute
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Id    : Token_Text) return Scheduled_Detail_View;

end HRA_N.Application.Scheduled_Detail_Query;
