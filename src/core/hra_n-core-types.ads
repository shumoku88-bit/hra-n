package HRA_N.Core.Types with
  SPARK_Mode => On
is
   pragma Pure;

   -- Exact Decimal Quanta: 1 Unit = 10^8 Quanta
   Scale : constant := 100_000_000;

   -- Operational bounds: up to 100 million units (~10^16 quanta).
   Max_Quanta_Value : constant := 10_000_000_000_000_000;
   Min_Quanta_Value : constant := -Max_Quanta_Value;

   type Quanta_Type is range Min_Quanta_Value .. Max_Quanta_Value;

   Zero_Quanta : constant Quanta_Type := 0;

   -- Bounded opaque token representation for identifiers
   Max_Token_Length : constant := 64;

   subtype Token_Length_Type is Natural range 0 .. Max_Token_Length;
   subtype Token_String_Type is String (1 .. Max_Token_Length);

   type Token_Text is record
      Length : Token_Length_Type := 0;
      Value  : Token_String_Type := [others => ' '];
   end record;

   function Make_Token (S : String) return Token_Text with
     Pre => S'Length <= Max_Token_Length;

   function Equal_Token (Left, Right : Token_Text) return Boolean is
     (Left.Length = Right.Length
      and then Left.Value (1 .. Left.Length) = Right.Value (1 .. Right.Length));

   -- Distinct semantic wrapper types (Loam ontology)
   type Locus_Id is record
      Token : Token_Text;
   end record;

   type Measure_Id is record
      Token : Token_Text;
   end record;

   type Event_Id is record
      Token : Token_Text;
   end record;

   type Effect_Key is record
      Token : Token_Text;
   end record;

end HRA_N.Core.Types;
