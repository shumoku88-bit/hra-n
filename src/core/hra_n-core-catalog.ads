-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Catalog
--
--  Human-facing catalog metadata: maps opaque coordinate identities
--  (Locus or Purpose) to display names and descriptive annotations.
--
--  Epistemic separation:
--    The catalog is *presentation evidence*, never admission evidence.
--    A coordinate absent from the catalog is not "unknown": the honest
--    label is the raw identity itself (see Display_Label fallback).
--    A catalog entry for a non-admitted coordinate is harmless historical
--    or preparatory metadata; it confers no recording authority.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Catalog with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Catalog_Entries : constant := 64;

   subtype Entry_Count_Type is Natural range 0 .. Max_Catalog_Entries;
   subtype Entry_Index_Type is Positive range 1 .. Max_Catalog_Entries;

   ----------------------------------------------------------------------------
   --  Bounded Description Text
   ----------------------------------------------------------------------------
   --  Descriptions are longer free-form annotations than identity tokens
   --  (real-world rows reach 78 UTF-8 bytes), so they require a wider bound.

   Max_Description_Length : constant := 128;

   subtype Description_Length_Type is Natural range 0 .. Max_Description_Length;
   subtype Description_String_Type is String (1 .. Max_Description_Length);

   type Description_Text is record
      Length : Description_Length_Type := 0;
      Value  : Description_String_Type := [others => ' '];
   end record;

   Empty_Description : constant Description_Text :=
     (Length => 0, Value => [others => ' ']);

   function Make_Description (S : String) return Description_Text with
     Pre => S'Length <= Max_Description_Length;

   function Equal_Description (Left, Right : Description_Text) return Boolean is
     (Left.Length = Right.Length
      and then Left.Value (1 .. Left.Length) = Right.Value (1 .. Right.Length));

   ----------------------------------------------------------------------------
   --  Catalog Entry and Memory
   ----------------------------------------------------------------------------

   type Catalog_Entry is record
      Id           : Token_Text;
      Display_Name : Token_Text;
      Description  : Description_Text;
   end record;

   Empty_Entry : constant Catalog_Entry :=
     (Id           => (Length => 0, Value => [others => ' ']),
      Display_Name => (Length => 0, Value => [others => ' ']),
      Description  => (Length => 0, Value => [others => ' ']));

   type Entry_Array is array (Entry_Index_Type) of Catalog_Entry;

   type Catalog_Memory is record
      Count   : Entry_Count_Type := 0;
      Entries : Entry_Array      := [others => Empty_Entry];
   end record;

   function Make_Catalog
     (Entries : Entry_Array;
      Count   : Entry_Count_Type) return Catalog_Memory;

   --  Structural invariant: an identity appears at most once (partial function).
   function Ids_Are_Unique (Mem : Catalog_Memory) return Boolean is
     (for all I in 1 .. Mem.Count =>
        (for all J in I + 1 .. Mem.Count =>
           not Equal_Token (Mem.Entries (I).Id, Mem.Entries (J).Id)));

   function Has_Entry
     (Mem : Catalog_Memory;
      Id  : Token_Text) return Boolean is
     (for some I in 1 .. Mem.Count =>
        Equal_Token (Mem.Entries (I).Id, Id));

   procedure Find_Entry
     (Mem   : Catalog_Memory;
      Id    : Token_Text;
      Value : out Catalog_Entry;
      Found : out Boolean);

   function Entry_Count (Mem : Catalog_Memory) return Entry_Count_Type is
     (Mem.Count);

   function Entry_At
     (Mem   : Catalog_Memory;
      Index : Entry_Index_Type) return Catalog_Entry
   with
     Pre => Index <= Mem.Count;

   ----------------------------------------------------------------------------
   --  Epistemically Honest Presentation
   ----------------------------------------------------------------------------

   --  Honest label: the curated display name when affirmative catalog
   --  evidence exists; otherwise the raw identity itself. The function
   --  never fabricates a placeholder such as "unclassified".
   function Display_Label
     (Mem : Catalog_Memory;
      Id  : Token_Text) return Token_Text;

end HRA_N.Core.Catalog;
