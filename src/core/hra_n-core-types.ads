-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Types
--
--  Fundamental types, exact decimal quanta, and bounded token identifiers.
--  Encodes Loam's orthogonal primitives without predefined accounting baggage.
-------------------------------------------------------------------------------

package HRA_N.Core.Types with
  SPARK_Mode => On
is
   pragma Pure;

   ----------------------------------------------------------------------------
   --  Exact Decimal Quanta
   ----------------------------------------------------------------------------

   --  Scaling factor: 1 whole unit = 10^8 quanta.
   --  Provides exact decimal arithmetic without binary floating-point loss.
   Scale : constant := 100_000_000;

   --  Operational bounds: up to 100,000,000 units (10^16 quanta).
   --  64-bit signed integer capacity (~9.22 * 10^18) guarantees that fold
   --  additions of up to 32 elements cannot overflow machine registers.
   Max_Quanta_Value : constant := 10_000_000_000_000_000;
   Min_Quanta_Value : constant := -Max_Quanta_Value;

   type Quanta_Type is range Min_Quanta_Value .. Max_Quanta_Value;

   Zero_Quanta : constant Quanta_Type := 0;

   ----------------------------------------------------------------------------
   --  Bounded Token Identifiers
   ----------------------------------------------------------------------------

   --  Maximum length for opaque identity tokens.
   Max_Token_Length : constant := 96;

   subtype Token_Length_Type is Natural range 0 .. Max_Token_Length;
   subtype Token_String_Type is String (1 .. Max_Token_Length);

   --  Opaque bounded string representation.
   type Token_Text is record
      Length : Token_Length_Type := 0;
      Value  : Token_String_Type := [others => ' '];
   end record;

   --  Construct a Token_Text from an ordinary string.
   function Make_Token (S : String) return Token_Text with
     Pre => S'Length <= Max_Token_Length;

   --  Strict equality check over the active prefix of two tokens.
   function Equal_Token (Left, Right : Token_Text) return Boolean is
     (Left.Length = Right.Length
      and then Left.Value (1 .. Left.Length) = Right.Value (1 .. Right.Length));

   --  Lexicographical less-than comparison over active prefix.
   function Token_Less (Left, Right : Token_Text) return Boolean;

   ----------------------------------------------------------------------------
   --  Orthogonal Semantic Coordinates (Loam Ontology)
   ----------------------------------------------------------------------------

   --  Locus: Where an effect is observed (opaque identity, not an account).
   type Locus_Id is record
      Token : Token_Text;
   end record;

   --  Measure: Unit of quantity (e.g. JPY, USD, Hours).
   type Measure_Id is record
      Token : Token_Text;
   end record;

   --  Event_Id: Stable identity of one recorded event.
   type Event_Id is record
      Token : Token_Text;
   end record;

   --  Effect_Key: Stable identity of one effect within an event.
   type Effect_Key is record
      Token : Token_Text;
   end record;

end HRA_N.Core.Types;
