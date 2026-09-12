-------------------------------------------------------------------------------
--  HRA-N: shared Actual record query
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Journal_Reader;

package HRA_N.Application.Actual_Query is

   type Actual_Scope is (Scope_Selected_Day, Scope_All);
   type Actual_Order is (Order_Oldest_First, Order_Newest_First);

   type Query is record
      Scope        : Actual_Scope := Scope_Selected_Day;
      Selected_Day : Date_Type;
      Ordering     : Actual_Order := Order_Newest_First;
   end record;

   Max_Actual_Rows : constant := 1024;
   subtype Actual_Row_Count is Natural range 0 .. Max_Actual_Rows;
   subtype Actual_Row_Index is Positive range 1 .. Max_Actual_Rows;

   type Actual_Row is record
      Event_Id    : Token_Text;
      Has_Date    : Boolean := False;
      Valid_On    : Date_Type;
      Description : Description_Text;
      Source_Order : Positive := 1;
   end record;

   Empty_Actual_Row : constant Actual_Row :=
     (Event_Id     => (Length => 0, Value => [others => ' ']),
      Has_Date     => False,
      Valid_On     => (Year => 2026, Month => 1, Day => 1),
      Description  => (Length => 0, Value => [others => ' ']),
      Source_Order => 1);

   type Actual_Row_Array is array (Actual_Row_Index) of Actual_Row;

   type Actual_View is record
      Status         : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot       : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Scope          : Actual_Scope := Scope_Selected_Day;
      Selected_Day   : Date_Type;
      Ordering       : Actual_Order := Order_Newest_First;
      Row_Count      : Actual_Row_Count := 0;
      Rows           : Actual_Row_Array := [others => Empty_Actual_Row];
      Diagnostic     : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len : Frontend_Types.Diagnostic_Length := 0;
   end record;

   function Project
     (Journal  : HRA_N.Storage.Journal_Reader.Journal_Result;
      Request  : Query;
      Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Actual_View;

   function Execute
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Request       : Query) return Actual_View;

end HRA_N.Application.Actual_Query;
