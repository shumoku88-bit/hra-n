with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver;

package HRA_N.Application.Actual_Detail_Query is

   type Effect_View is record
      Locus   : Token_Text;
      Measure : Token_Text;
      Amount  : Quanta_Type := 0;
   end record;

   Empty_Effect_View : constant Effect_View :=
     (Locus   => (Length => 0, Value => [others => ' ']),
      Measure => (Length => 0, Value => [others => ' ']),
      Amount  => 0);

   type Effect_View_Array is array (Effect_Index_Type) of Effect_View;

   type Actual_Detail_View is record
      Status         : Frontend_Types.Query_Status :=
        Frontend_Types.Query_Rejected;
      Snapshot       : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned);
      Event_Id       : Token_Text;
      Has_Date       : Boolean := False;
      Valid_On       : Date_Type;
      Description    : Description_Text;
      Has_Purpose    : Boolean := False;
      Purpose        : Token_Text;
      Has_Replaces   : Boolean := False;
      Replaces       : Token_Text;
      Has_Relation   : Boolean := False;
      Relation       : Token_Text;
      Has_Discharge  : Boolean := False;
      Discharge      : Token_Text;
      Effect_Count   : Effect_Count_Type := 0;
      Effects        : Effect_View_Array := [others => Empty_Effect_View];
      Diagnostic     : Frontend_Types.Diagnostic_Text := [others => ' '];
      Diagnostic_Len : Frontend_Types.Diagnostic_Length := 0;
   end record;

   --  Re-read the journal and resolve one visible identity. A missing identity
   --  is rejected rather than interpreted from a cached frontend row.
   function Execute
     (Paths    : HRA_N.Application.Path_Resolver.Path_Config;
      Event_Id : Token_Text) return Actual_Detail_View;

end HRA_N.Application.Actual_Detail_Query;
