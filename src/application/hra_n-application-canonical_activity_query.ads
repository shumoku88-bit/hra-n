------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Canonical_Activity_Query
--
--  One immutable read-only browser snapshot over canonical actual.loam.
--  Balance and coordinate activity projections are derived from the same
--  admitted byte image, so a GUI never mixes two independently reopened
--  authorities in one screen.
-------------------------------------------------------------------------------

with Ada.Finalization;
with HRA_N.Application.Canonical_Balance_Query;
with HRA_N.Core.Description;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity;
with HRA_N.Storage.Loam_Actual_Reader;

package HRA_N.Application.Canonical_Activity_Query is

   Max_Activity_Rows : constant := 1024;
   subtype Activity_Count is Natural range 0 .. Max_Activity_Rows;
   subtype Activity_Index is Positive range 1 .. Max_Activity_Rows;

   type Activity_Row is record
      Event             : Event_Id;
      Valid_On          : HRA_N.Core.Validity.Date_Type;
      Has_Description   : Boolean := False;
      Description       : HRA_N.Core.Description.Description_Text;
      Net_Change        : Long_Long_Integer := 0;
      Posting_Count     : Natural := 0;
      Is_Superseded     : Boolean := False;
      Successor         : Event_Id;
      Is_Replacement    : Boolean := False;
      Replaces          : Event_Id;
      Is_Reversal       : Boolean := False;
      Reverses          : Event_Id;
      Has_Reverser      : Boolean := False;
      Reversed_By       : Event_Id;
   end record;

   Empty_Activity_Row : constant Activity_Row :=
     (Event           => (Token => (Length => 0, Value => [others => ' '])),
      Valid_On        => (Year => 2026, Month => 1, Day => 1),
      Has_Description => False,
      Description     => (Length => 0, Value => [others => ' ']),
      Net_Change      => 0,
      Posting_Count   => 0,
      Is_Superseded   => False,
      Successor       => (Token => (Length => 0, Value => [others => ' '])),
      Is_Replacement  => False,
      Replaces        => (Token => (Length => 0, Value => [others => ' '])),
      Is_Reversal     => False,
      Reverses        => (Token => (Length => 0, Value => [others => ' '])),
      Has_Reverser    => False,
      Reversed_By     => (Token => (Length => 0, Value => [others => ' '])));

   type Activity_Array is array (Activity_Index) of Activity_Row;

   type Activity_View is record
      Success          : Boolean := False;
      Rows             : Activity_Array := [others => Empty_Activity_Row];
      Count            : Activity_Count := 0;
      Active_Count     : Natural := 0;
      Superseded_Count : Natural := 0;
      Diagnostic       : String (1 .. 192) := [others => ' '];
      Diagnostic_Len   : Natural := 0;
   end record;

   type Browser_Snapshot is private;

   function Open (Root_Path : String) return Browser_Snapshot;

   function Ready (Source : Browser_Snapshot) return Boolean;

   function Diagnostic (Source : Browser_Snapshot) return String;

   function Balance
     (Source : Browser_Snapshot)
      return HRA_N.Application.Canonical_Balance_Query.Balance_View;

   function Activity_For
     (Source  : Browser_Snapshot;
      Locus   : Locus_Id;
      Measure : Measure_Id) return Activity_View;

private

   type Snapshot_Data;
   type Snapshot_Data_Access is access Snapshot_Data;

   type Browser_Snapshot is new Ada.Finalization.Controlled with record
      Data : Snapshot_Data_Access := null;
   end record;

   overriding procedure Adjust (Source : in out Browser_Snapshot);
   overriding procedure Finalize (Source : in out Browser_Snapshot);

   type Snapshot_Data is record
      References : Positive := 1;
      Is_Ready   : Boolean := False;
      Actual     : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result;
      Balances   : HRA_N.Application.Canonical_Balance_Query.Balance_View;
      Message    : String (1 .. 192) := [others => ' '];
      Msg_Len    : Natural := 0;
   end record;

end HRA_N.Application.Canonical_Activity_Query;
