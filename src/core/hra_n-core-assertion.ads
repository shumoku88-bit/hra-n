-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Assertion
--
--  Append-only balance assertion evidence.
--  Records physical observations of balances at a specific coordinate and day.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;

package HRA_N.Core.Assertion with
  SPARK_Mode => On
is
   pragma Pure;

   type Assertion_Id is record
      Token : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   type Balance_Assertion is record
      Id          : Assertion_Id;
      Valid_On    : Date_Type;
      Coordinate  : Coordinate_Type;
      Amount      : Quanta_Type := 0;
      Description : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   function Empty_Assertion return Balance_Assertion is
     ((Id          => (Token => (Length => 0, Value => [others => ' '])),
       Valid_On    => (Year => 2026, Month => 1, Day => 1),
       Coordinate  => (Locus   => (Token => (Length => 0, Value => [others => ' '])),
                       Measure => (Token => (Length => 0, Value => [others => ' ']))),
       Amount      => 0,
       Description => (Length => 0, Value => [others => ' '])));

   Max_Assertions : constant := 256;
   subtype Assertion_Count is Natural range 0 .. Max_Assertions;
   subtype Assertion_Index is Positive range 1 .. Max_Assertions;
   type Assertion_Array is array (Assertion_Index) of Balance_Assertion;

   type Assertion_Memory is record
      Count  : Assertion_Count := 0;
      Values : Assertion_Array := [others => Empty_Assertion];
   end record;

   function Assertions_Are_Unique (Memory : Assertion_Memory) return Boolean is
     (for all I in 1 .. Memory.Count =>
        (for all J in I + 1 .. Memory.Count =>
           not Equal_Token (Memory.Values (I).Id.Token,
                            Memory.Values (J).Id.Token)));

   procedure Add_Assertion
     (Memory  : in out Assertion_Memory;
      Item    : Balance_Assertion;
      Success : out Boolean);

   procedure Find_Assertion
     (Memory : Assertion_Memory;
      Id     : Assertion_Id;
      Item   : out Balance_Assertion;
      Found  : out Boolean);

   procedure Find_Latest_Assertion
     (Memory : Assertion_Memory;
      Coord  : Coordinate_Type;
      As_Of  : Date_Type;
      Item   : out Balance_Assertion;
      Found  : out Boolean);

end HRA_N.Core.Assertion;
