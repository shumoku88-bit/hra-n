-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Actual_Reversal
--
--  Explicit Reversal provenance binding target events to their inverse cancellations.
--  Encodes Loam's LOAM-ACTUAL-REVERSAL-MEMORY v1 ontology:
--    REVERSE <Target_Event_Id> <Reversal_Event_Id>
--
--  Invariants:
--    Target and Reversal event IDs must be valid non-empty tokens.
--    Target /= Reversal (an event cannot revert itself).
--    Endpoints are unique (no target is reversed twice, no reversal reverts two targets).
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Actual_Reversal with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Reversals : constant := 256;

   subtype Reversal_Count_Type is Natural range 0 .. Max_Reversals;
   subtype Reversal_Index_Type is Positive range 1 .. Max_Reversals;

   type Actual_Reversal is record
      Target   : Event_Id;
      Reversal : Event_Id;
   end record;

   Empty_Reversal : constant Actual_Reversal :=
     (Target   => (Token => (Length => 0, Value => [others => ' '])),
      Reversal => (Token => (Length => 0, Value => [others => ' '])));

   type Reversal_Array is array (Reversal_Index_Type) of Actual_Reversal;

   type Reversal_Memory is record
      Count   : Reversal_Count_Type := 0;
      Entries : Reversal_Array      := [others => Empty_Reversal];
   end record;

   function Valid_Endpoints (Rev : Actual_Reversal) return Boolean is
     (Rev.Target.Token.Length > 0
      and then Rev.Reversal.Token.Length > 0
      and then not Equal_Token (Rev.Target.Token, Rev.Reversal.Token));

   function Endpoints_Are_Unique (Mem : Reversal_Memory) return Boolean is
     (for all I in 1 .. Mem.Count =>
        (for all J in I + 1 .. Mem.Count =>
           not Equal_Token (Mem.Entries (I).Target.Token, Mem.Entries (J).Target.Token)
           and then not Equal_Token (Mem.Entries (I).Reversal.Token, Mem.Entries (J).Reversal.Token)));

   function Is_Target_Reversed
     (Mem    : Reversal_Memory;
      Target : Event_Id) return Boolean;

   procedure Find_Reversal_For
     (Mem      : Reversal_Memory;
      Target   : Event_Id;
      Reversal : out Event_Id;
      Found    : out Boolean);

   function Entry_Count (Mem : Reversal_Memory) return Reversal_Count_Type is
     (Mem.Count);

   function Entry_At
     (Mem   : Reversal_Memory;
      Index : Reversal_Index_Type) return Actual_Reversal
   with
     Pre => Index <= Mem.Count;

end HRA_N.Core.Actual_Reversal;
