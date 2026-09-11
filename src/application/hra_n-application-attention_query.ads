-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Attention_Query
--
--  Shared current-open attention query over one admitted snapshot.
--  Storage order is representation order only: no due sorting, no
--  priority, no selected-day membership. The three due meanings stay
--  distinct in every rendered row.
-------------------------------------------------------------------------------

with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Application.Attention_Query is

   Max_Query_Rows : constant := 64;

   type Attention_Row is record
      Id      : Token_Text;
      Context : Description_Text;
      Due     : Attention_Due;
   end record;

   type Row_Array is array (Positive range 1 .. Max_Query_Rows) of Attention_Row;

   type Attention_View is record
      Status    : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Success   : Boolean := False;
      Snapshot  : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Count     : Natural := 0;
      Rows      : Row_Array :=
        [others => (Id      => (Length => 0, Value => [others => ' ']),
                    Context => (Length => 0,
                                Value  => [1 .. Max_Description_Length => ' ']),
                    Due     => (Kind => Due_Undetermined))];
      Diagnostic     : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len : Frontend_Types.Diagnostic_Length := 0;
   end record;

   function Execute (Paths : Path_Config) return Attention_View;

   --  Shared due rendering so every frontend labels one meaning one way.
   function Due_Label (Due : Attention_Due) return String;

end HRA_N.Application.Attention_Query;
