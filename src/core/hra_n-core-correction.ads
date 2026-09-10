with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Correction with SPARK_Mode => On is
   pragma Pure;
   type Correction_Id is record Token : Token_Text; end record;
   type Event_Correction is record
      Id : Correction_Id;
      Target : Event_Id;
      Replacement : Event_Id;
   end record;
   Empty_Correction : constant Event_Correction :=
     (Id => (Token => (Length => 0, Value => [others => ' '])),
      Target => (Token => (Length => 0, Value => [others => ' '])),
      Replacement => (Token => (Length => 0, Value => [others => ' '])));
   Max_Corrections : constant := 256;
   subtype Correction_Count is Natural range 0 .. Max_Corrections;
   subtype Correction_Index is Positive range 1 .. Max_Corrections;
   type Correction_Array is array (Correction_Index) of Event_Correction;
   type Correction_Memory is record
      Count : Correction_Count := 0;
      Values : Correction_Array := [others => Empty_Correction];
   end record;
   function Ids_Are_Unique (Memory : Correction_Memory) return Boolean is
     (for all I in 1 .. Memory.Count =>
        (for all J in I + 1 .. Memory.Count =>
           not Equal_Token (Memory.Values (I).Id.Token,
                            Memory.Values (J).Id.Token)));
end HRA_N.Core.Correction;
