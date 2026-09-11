with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Transaction_Metadata with
  SPARK_Mode => On
is
   pragma Pure;

   type Optional_Token is record
      Present : Boolean := False;
      Value   : Token_Text;
   end record;

   type Optional_Event_Id is record
      Present : Boolean := False;
      Value   : Event_Id;
   end record;

   type Transaction_Metadata_Entry is record
      Event       : Event_Id;
      Purpose     : Optional_Token;
      Replaces    : Optional_Event_Id;
      Relation    : Optional_Token;
      Discharge   : Optional_Token;
   end record;

   Max_Metadata_Entries : constant := 1024;
   subtype Metadata_Count is Natural range 0 .. Max_Metadata_Entries;
   subtype Metadata_Index is Positive range 1 .. Max_Metadata_Entries;
   type Metadata_Array is array (Metadata_Index) of Transaction_Metadata_Entry;

   Empty_Entry : constant Transaction_Metadata_Entry :=
     (Event     => (Token => (Length => 0, Value => [others => ' '])),
      Purpose   => (Present => False, Value => (Length => 0, Value => [others => ' '])),
      Replaces  => (Present => False,
                    Value => (Token => (Length => 0, Value => [others => ' ']))),
      Relation  => (Present => False, Value => (Length => 0, Value => [others => ' '])),
      Discharge => (Present => False, Value => (Length => 0, Value => [others => ' '])));

   type Metadata_List is record
      Count  : Metadata_Count := 0;
      Values : Metadata_Array := [others => Empty_Entry];
   end record;

   function Metadata_Event_Ids_Are_Unique (Entries : Metadata_List) return Boolean;
   function Replacement_References_Are_Closed (Entries : Metadata_List) return Boolean;
   function Replacements_Are_One_To_One (Entries : Metadata_List) return Boolean;
   function Replacements_Are_Acyclic (Entries : Metadata_List) return Boolean;

   type Metadata_Memory is private;

   function Make_Metadata_Memory (Entries : Metadata_List) return Metadata_Memory
   with Pre => Metadata_Event_Ids_Are_Unique (Entries);

   function Entry_Count (Memory : Metadata_Memory) return Metadata_Count;

   procedure Find_Metadata
     (Memory : in Metadata_Memory;
      Event  : in Event_Id;
      Item   : out Transaction_Metadata_Entry;
      Found  : out Boolean);

private
   type Metadata_Memory is record
      Entries : Metadata_List;
   end record;

   function Entry_Count (Memory : Metadata_Memory) return Metadata_Count is
     (Memory.Entries.Count);
end HRA_N.Core.Transaction_Metadata;
