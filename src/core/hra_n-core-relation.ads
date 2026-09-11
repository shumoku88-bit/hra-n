-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Relation
--
--  Directional household relation claims and their discharges. A claim
--  anchors one positive face amount to a retained source transaction
--  between two endpoints, one of which is always the household. A
--  discharge is fulfillment provenance from a settlement transaction to
--  a claim: one normalized row per (settlement, claim) pair, no separate
--  discharge identity. Aggregate discharges never exceed the face amount.
--  Neither revisions nor effect-level anchoring are modeled; they must
--  earn their place through a concrete use.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Relation with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Relations  : constant := 256;
   Max_Discharges : constant := 256;

   type Endpoint_Kind is (Endpoint_Household, Endpoint_External);

   type Relation_Endpoint is record
      Kind : Endpoint_Kind := Endpoint_Household;
      Name : Token_Text;
   end record;

   Empty_Endpoint : constant Relation_Endpoint :=
     (Kind => Endpoint_Household,
      Name => (Length => 0, Value => [others => ' ']));

   function Household_Endpoint return Relation_Endpoint is
     ((Kind => Endpoint_Household,
       Name => (Length => 0, Value => [others => ' '])));

   function External_Endpoint (Name : Token_Text) return Relation_Endpoint is
     ((Kind => Endpoint_External, Name => Name));

   function Equal_Endpoint
     (Left, Right : Relation_Endpoint) return Boolean is
     (Left.Kind = Right.Kind
      and then (Left.Kind = Endpoint_Household
                or else Equal_Token (Left.Name, Right.Name)));

   type Relation_Claim is record
      Id        : Token_Text;
      Source    : Event_Id;
      Debtor    : Relation_Endpoint;
      Creditor  : Relation_Endpoint;
      Measure   : Token_Text;
      Face      : Quanta_Type;
   end record;

   Empty_Claim : constant Relation_Claim :=
     (Id       => (Length => 0, Value => [others => ' ']),
      Source   => (Token => (Length => 0, Value => [others => ' '])),
      Debtor   => (Kind => Endpoint_Household,
                   Name => (Length => 0, Value => [others => ' '])),
      Creditor => (Kind => Endpoint_Household,
                   Name => (Length => 0, Value => [others => ' '])),
      Measure  => (Length => 0, Value => [others => ' ']),
      Face     => Zero_Quanta);

   type Claim_Discharge is record
      Settlement : Event_Id;
      Target     : Token_Text;
      Amount     : Quanta_Type;
   end record;

   Empty_Discharge : constant Claim_Discharge :=
     (Settlement => (Token => (Length => 0, Value => [others => ' '])),
      Target     => (Length => 0, Value => [others => ' ']),
      Amount     => Zero_Quanta);

   subtype Claim_Count_Type is Natural range 0 .. Max_Relations;
   subtype Claim_Index_Type is Positive range 1 .. Max_Relations;
   type Claim_Array is array (Claim_Index_Type) of Relation_Claim;

   subtype Discharge_Count_Type is Natural range 0 .. Max_Discharges;
   subtype Discharge_Index_Type is Positive range 1 .. Max_Discharges;
   type Discharge_Array is array (Discharge_Index_Type) of Claim_Discharge;

   type Relation_Memory is record
      Claim_Count     : Claim_Count_Type := 0;
      Claims          : Claim_Array      := [others => Empty_Claim];
      Discharge_Count : Discharge_Count_Type := 0;
      Discharges      : Discharge_Array  := [others => Empty_Discharge];
   end record;

   function Claim_Ids_Are_Unique (Mem : Relation_Memory) return Boolean;
   function Discharge_Pairs_Are_Unique (Mem : Relation_Memory) return Boolean;

   --  Total discharged against one claim across all retained rows.
   --  Bounded by construction: at most Max_Discharges rows of at most
   --  one maximum quantity each.
   function Discharged_Against
     (Mem      : Relation_Memory;
      Claim_Id : Token_Text) return Long_Long_Integer
   with
     Post =>
       Discharged_Against'Result
         >= Long_Long_Integer (Max_Discharges)
            * Long_Long_Integer (Min_Quanta_Value)
       and then Discharged_Against'Result
         <= Long_Long_Integer (Max_Discharges)
            * Long_Long_Integer (Max_Quanta_Value);

   --  Remaining face: positive while the claim is open.
   function Remaining_For
     (Mem      : Relation_Memory;
      Claim_Id : Token_Text) return Long_Long_Integer;

   function Involves_Event
     (Mem    : Relation_Memory;
      Target : Event_Id) return Boolean;

   procedure Find_Claim
     (Mem   : Relation_Memory;
      Id    : Token_Text;
      Claim : out Relation_Claim;
      Found : out Boolean);

end HRA_N.Core.Relation;
