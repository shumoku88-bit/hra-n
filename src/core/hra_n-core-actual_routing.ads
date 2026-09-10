-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Routing
--
--  Expense-to-Purpose routing ontology compatible with Loam's LOAM-ACTUAL-ROUTING 1.
--  Routes expense loci to budget envelope purposes (e.g. food -> 食費).
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Routing with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Routing_Entries : constant := 128;

   type Routing_Entry is record
      Locus   : Locus_Id;
      Purpose : Token_Text;
   end record;

   Empty_Routing_Entry : constant Routing_Entry :=
     (Locus   => (Token => (Length => 0, Value => [others => ' '])),
      Purpose => (Length => 0, Value => [others => ' ']));

   subtype Routing_Count_Type is Natural range 0 .. Max_Routing_Entries;
   subtype Routing_Index_Type is Positive range 1 .. Max_Routing_Entries;
   type Routing_Array is array (Routing_Index_Type) of Routing_Entry;

   type Routing_Map is record
      Count   : Routing_Count_Type := 0;
      Entries : Routing_Array      := [others => Empty_Routing_Entry];
   end record;

   procedure Find_Purpose
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      Purpose : out Token_Text;
      Found   : out Boolean);

   function Is_Managed
     (Map   : Routing_Map;
      Locus : Locus_Id) return Boolean;

   function Purpose_Matches
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      Purpose : Token_Text) return Boolean;

end HRA_N.Core.Actual_Routing;
