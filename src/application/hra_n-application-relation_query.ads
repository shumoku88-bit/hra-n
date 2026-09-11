-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Relation_Query
--
--  Shared open-claim query over one admitted snapshot. A claim is open
--  while its remaining face is positive and its source event is still
--  effective; discharges count while their settlement is effective.
--  Correcting a referenced event therefore re-derives the answer without
--  any new fact. Rows follow retained order.
-------------------------------------------------------------------------------

with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Application.Relation_Query is

   Max_Query_Rows : constant := 64;

   type Claim_Row is record
      Id        : Token_Text;
      Source    : Token_Text;
      Debtor    : Relation_Endpoint;
      Creditor  : Relation_Endpoint;
      Measure   : Token_Text;
      Face      : Quanta_Type := Zero_Quanta;
      Remaining : Quanta_Type := Zero_Quanta;
   end record;

   type Row_Array is array (Positive range 1 .. Max_Query_Rows) of Claim_Row;

   type Relation_View is record
      Status    : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Success   : Boolean := False;
      Snapshot  : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Count     : Natural := 0;
      Rows      : Row_Array;
      Diagnostic     : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  All open claims, or every retained claim when Open_Only is False.
   function Execute
     (Paths     : Path_Config;
      Open_Only : Boolean := True) return Relation_View;

   Max_Linked_Rows : constant := 8;

   --  One claim sourced at the linked event with its effective remaining.
   type Linked_Claim is record
      Id        : Token_Text;
      Debtor    : Relation_Endpoint;
      Creditor  : Relation_Endpoint;
      Measure   : Token_Text;
      Remaining : Quanta_Type := Zero_Quanta;
   end record;

   --  One discharge settled by the linked event.
   type Linked_Discharge is record
      Claim  : Token_Text;
      Amount : Quanta_Type := Zero_Quanta;
   end record;

   type Linked_Claim_Array is
     array (Positive range 1 .. Max_Linked_Rows) of Linked_Claim;
   type Linked_Discharge_Array is
     array (Positive range 1 .. Max_Linked_Rows) of Linked_Discharge;

   --  Single home for the per-event link rule: claims sourced here plus
   --  discharges settled here, both effectiveness-aware. Capped display
   --  rows travel with exact totals so renderers can say "and N more".
   type Event_Links is record
      Success         : Boolean := False;
      Claim_Total     : Natural := 0;
      Claims          : Linked_Claim_Array;
      Claim_Shown     : Natural := 0;
      Discharge_Total : Natural := 0;
      Discharges      : Linked_Discharge_Array;
      Discharge_Shown : Natural := 0;
   end record;

   function Links_For_Event
     (Paths    : Path_Config;
      Event_Id : Token_Text) return Event_Links;

   --  Shared endpoint rendering so every frontend names one side one way.
   function Endpoint_Label (Endpoint : Relation_Endpoint) return String;

end HRA_N.Application.Relation_Query;
