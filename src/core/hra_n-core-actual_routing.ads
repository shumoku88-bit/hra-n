-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Routing
--
--  Historical Actual Locus-to-Purpose routing. Each retained assertion has an
--  explicit effective coordinate and may state either managed or unmanaged.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Core.Actual_Routing with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Routing_Entries : constant := 256;

   type Routing_Effective_Kind is (Routing_Initial, Routing_From_Date);

   type Routing_Entry is record
      Locus          : Locus_Id;
      Effective_Kind : Routing_Effective_Kind := Routing_Initial;
      Effective_On   : Date_Type := (Year => 1900, Month => 1, Day => 1);
      Managed        : Boolean := False;
      Purpose        : Token_Text;
   end record;

   Empty_Routing_Entry : constant Routing_Entry :=
     (Locus          => (Token => (Length => 0, Value => [others => ' '])),
      Effective_Kind => Routing_Initial,
      Effective_On   => (Year => 1900, Month => 1, Day => 1),
      Managed        => False,
      Purpose        => (Length => 0, Value => [others => ' ']));

   subtype Routing_Count_Type is Natural range 0 .. Max_Routing_Entries;
   subtype Routing_Index_Type is Positive range 1 .. Max_Routing_Entries;
   type Routing_Array is array (Routing_Index_Type) of Routing_Entry;

   type Routing_Map is record
      Count   : Routing_Count_Type := 0;
      Entries : Routing_Array      := [others => Empty_Routing_Entry];
   end record;

   --  No two retained assertions may claim the same locus/effective
   --  coordinate. File order therefore carries no authority.
   function Coordinates_Are_Unique (Map : Routing_Map) return Boolean;

   procedure Find_Purpose_As_Of
     (Map     : Routing_Map;
      Locus   : Locus_Id;
      As_Of   : Date_Type;
      Purpose : out Token_Text;
      Found   : out Boolean);

   --  Compatibility projection selecting the latest retained assertion.
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
