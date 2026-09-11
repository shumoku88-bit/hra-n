-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Attention
--
--  Retained household attention items: matters that may need action even
--  when no financial occurrence exists. Due meaning is not an optional
--  date: a dated due, no due date, and an undetermined due stay distinct.
--  Closure is explicit lifecycle evidence, at most one per item. Relation
--  provenance is retained elsewhere and never closes an item.
-------------------------------------------------------------------------------

with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Core.Attention with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Attention_Items : constant := 256;

   type Due_Kind is (Due_On_Date, No_Due_Date, Due_Undetermined);

   type Attention_Due (Kind : Due_Kind := Due_Undetermined) is record
      case Kind is
         when Due_On_Date =>
            Due_Date : Date_Type;
         when No_Due_Date | Due_Undetermined =>
            null;
      end case;
   end record;

   type Closure_Kind is (Closure_Resolved, Closure_Dropped);

   type Attention_Item is record
      Id      : Token_Text;
      Context : Description_Text;
      Due     : Attention_Due;
   end record;

   Empty_Item : constant Attention_Item :=
     (Id      => (Length => 0, Value => [others => ' ']),
      Context => (Length => 0, Value => [1 .. Max_Description_Length => ' ']),
      Due     => (Kind => Due_Undetermined));

   type Attention_Closure is record
      Target   : Token_Text;
      Kind     : Closure_Kind;
      Known_On : Date_Type;
   end record;

   Empty_Closure : constant Attention_Closure :=
     (Target   => (Length => 0, Value => [others => ' ']),
      Kind     => Closure_Resolved,
      Known_On => (Year => 2026, Month => 1, Day => 1));

   subtype Item_Count_Type is Natural range 0 .. Max_Attention_Items;
   subtype Item_Index_Type is Positive range 1 .. Max_Attention_Items;
   type Item_Array is array (Item_Index_Type) of Attention_Item;
   type Closure_Array is array (Item_Index_Type) of Attention_Closure;

   type Attention_Memory is record
      Item_Count : Item_Count_Type := 0;
      Items      : Item_Array      := [others => Empty_Item];
      Close_Count : Item_Count_Type := 0;
      Closures   : Closure_Array   := [others => Empty_Closure];
   end record;

   function Item_Ids_Are_Unique (Mem : Attention_Memory) return Boolean;
   function Closure_References_Are_Closed (Mem : Attention_Memory) return Boolean;
   function Closures_Are_One_To_One (Mem : Attention_Memory) return Boolean;

   function Has_Closure
     (Mem : Attention_Memory;
      Id  : Token_Text) return Boolean;

   function Is_Open
     (Mem : Attention_Memory;
      Id  : Token_Text) return Boolean;

   function Open_Count (Mem : Attention_Memory) return Item_Count_Type;

   procedure Find_Item
     (Mem   : Attention_Memory;
      Id    : Token_Text;
      Item  : out Attention_Item;
      Found : out Boolean);

   procedure Find_Closure
     (Mem     : Attention_Memory;
      Id      : Token_Text;
      Closure : out Attention_Closure;
      Found   : out Boolean);

end HRA_N.Core.Attention;
