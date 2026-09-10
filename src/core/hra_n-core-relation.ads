-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Relation
--
--  Raw provenance for directional household open relations and their exact
--  discharge correspondences. Positivity, source resolution, coverage, and
--  discharge bounds are Application admission laws, not construction laws.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Relation with
  SPARK_Mode => On
is
   pragma Pure;

   type Endpoint_Kind is (Endpoint_Household, Endpoint_External);

   type Relation_Endpoint (Kind : Endpoint_Kind := Endpoint_Household) is record
      case Kind is
         when Endpoint_Household =>
            null;
         when Endpoint_External =>
            External_Id : Token_Text;
      end case;
   end record;

   Household_Endpoint : constant Relation_Endpoint :=
     (Kind => Endpoint_Household);

   function External_Endpoint (Id : Token_Text) return Relation_Endpoint is
     ((Kind => Endpoint_External, External_Id => Id));

   function Endpoint_Is_Well_Formed (Endpoint : Relation_Endpoint) return Boolean is
     (Endpoint.Kind = Endpoint_Household
      or else Endpoint.External_Id.Length > 0);

   --  Currently earned relation geometry: exactly one Household endpoint.
   function Endpoints_Are_Admissible
     (Debtor, Creditor : Relation_Endpoint) return Boolean is
     (Endpoint_Is_Well_Formed (Debtor)
      and then Endpoint_Is_Well_Formed (Creditor)
      and then Debtor.Kind /= Creditor.Kind);

   type Relation_Unit is record
      Id            : Token_Text;
      Source_Event  : Event_Id;
      Source_Effect : Effect_Key;
      Debtor        : Relation_Endpoint;
      Creditor      : Relation_Endpoint;
      Quantity      : Quanta_Type := Zero_Quanta;
   end record;

   Empty_Unit : constant Relation_Unit :=
     (Id            => (Length => 0, Value => [others => ' ']),
      Source_Event  => (Token => (Length => 0, Value => [others => ' '])),
      Source_Effect => (Token => (Length => 0, Value => [others => ' '])),
      Debtor        => (Kind => Endpoint_Household),
      Creditor      => (Kind => Endpoint_Household),
      Quantity      => Zero_Quanta);

   Max_Relation_Units : constant := 256;
   subtype Unit_Count_Type is Natural range 0 .. Max_Relation_Units;
   subtype Unit_Index_Type is Positive range 1 .. Max_Relation_Units;
   type Unit_Array is array (Unit_Index_Type) of Relation_Unit;

   type Unit_Memory is record
      Count : Unit_Count_Type := 0;
      Units : Unit_Array      := [others => Empty_Unit];
   end record;

   function Unit_Ids_Are_Unique (Mem : Unit_Memory) return Boolean is
     (for all I in 1 .. Mem.Count =>
        (for all J in I + 1 .. Mem.Count =>
           not Equal_Token (Mem.Units (I).Id, Mem.Units (J).Id)));

   procedure Find_Unit
     (Mem   : Unit_Memory;
      Id    : Token_Text;
      Value : out Relation_Unit;
      Found : out Boolean);

   type Relation_Discharge is record
      Event    : Event_Id;
      Target   : Token_Text;
      Quantity : Quanta_Type := Zero_Quanta;
   end record;

   Empty_Discharge : constant Relation_Discharge :=
     (Event    => (Token => (Length => 0, Value => [others => ' '])),
      Target   => (Length => 0, Value => [others => ' ']),
      Quantity => Zero_Quanta);

   Max_Relation_Discharges : constant := 512;
   subtype Discharge_Count_Type is Natural range 0 .. Max_Relation_Discharges;
   subtype Discharge_Index_Type is Positive range 1 .. Max_Relation_Discharges;
   type Discharge_Array is array (Discharge_Index_Type) of Relation_Discharge;

   type Discharge_Memory is record
      Count      : Discharge_Count_Type := 0;
      Discharges : Discharge_Array      := [others => Empty_Discharge];
   end record;

   --  Raw persistence may retain duplicate pairs. Application admission uses
   --  this predicate only after Event activation for one target.
   function Discharge_Pairs_Are_Unique (Mem : Discharge_Memory) return Boolean is
     (for all I in 1 .. Mem.Count =>
        (for all J in I + 1 .. Mem.Count =>
           not (Equal_Token
                  (Mem.Discharges (I).Event.Token,
                   Mem.Discharges (J).Event.Token)
                and then Equal_Token
                  (Mem.Discharges (I).Target,
                   Mem.Discharges (J).Target))));

end HRA_N.Core.Relation;
