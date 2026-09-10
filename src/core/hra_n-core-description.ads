-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Description
--
--  Event description evidence linking EventId to human-readable memo text.
--
--  Design Rationale (derived from Loam Observation 111 & Architecture):
--  Events remain neutral identifiers with balanced movement effects.
--  Descriptions are independently observable narrative metadata.
--  Each EventId has at most one description record (Nodup invariant).
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Description with
  SPARK_Mode => On
is
   pragma Pure;

   ----------------------------------------------------------------------------
   --  Description Text Types
   ----------------------------------------------------------------------------

   Max_Description_Length : constant := 512;

   subtype Description_Length_Type is Natural range 0 .. Max_Description_Length;
   subtype Description_String      is String (1 .. Max_Description_Length);

   type Description_Text is record
      Length : Description_Length_Type := 0;
      Value  : Description_String      := [others => ' '];
   end record;

   function Make_Description (S : String) return Description_Text
   with
     Pre => S'Length <= Max_Description_Length;

   function To_String (D : Description_Text) return String is
     (D.Value (1 .. D.Length));

   function Equal_Description (Left, Right : Description_Text) return Boolean is
     (Left.Length = Right.Length
      and then Left.Value (1 .. Left.Length) = Right.Value (1 .. Right.Length));

   ----------------------------------------------------------------------------
   --  Description Memory Entry & Collections
   ----------------------------------------------------------------------------

   type Description_Entry is record
      Event_Id : Types.Event_Id;
      Text     : Description_Text;
   end record;

   Max_Description_Entries : constant := 1024;

   subtype Description_Count_Type is Natural range 0 .. Max_Description_Entries;
   subtype Description_Index_Type is Positive range 1 .. Max_Description_Entries;

   type Description_Array is array (Description_Index_Type) of Description_Entry;

   type Description_Entry_List is record
      Count  : Description_Count_Type := 0;
      Values : Description_Array      := [others =>
                 (Event_Id => (Token => (Length => 0, Value => [others => ' '])),
                  Text     => (Length => 0, Value => [others => ' ']))];
   end record;

   --  Specification invariant: each EventId has at most one description entry.
   function Event_Ids_Are_Unique (Entries : Description_Entry_List) return Boolean is
     (for all I in 1 .. Entries.Count =>
        (for all J in I + 1 .. Entries.Count =>
           not Equal_Token (Entries.Values (I).Event_Id.Token,
                            Entries.Values (J).Event_Id.Token)));

   ----------------------------------------------------------------------------
   --  Encapsulated Description Memory
   ----------------------------------------------------------------------------

   type Description_Memory is private;

   function Make_Description_Memory
     (Entries : Description_Entry_List) return Description_Memory
   with
     Pre => Event_Ids_Are_Unique (Entries);

   function Entry_Count (Memory : Description_Memory) return Description_Count_Type;

   function Entry_At
     (Memory : Description_Memory;
      Index  : Description_Index_Type) return Description_Entry
   with
     Pre => Index <= Entry_Count (Memory);

   --  Look up description text for an EventId.
   procedure Find_Description
     (Memory : in  Description_Memory;
      Ev_Id  : in  Types.Event_Id;
      Text   : out Description_Text;
      Found  : out Boolean);

private

   type Description_Memory is record
      Entries : Description_Entry_List;
   end record;

   function Entry_Count (Memory : Description_Memory) return Description_Count_Type is
     (Memory.Entries.Count);

   function Entry_At
     (Memory : Description_Memory;
      Index  : Description_Index_Type) return Description_Entry is
     (Memory.Entries.Values (Index));

end HRA_N.Core.Description;
