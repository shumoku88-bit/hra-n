with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Quantity; use HRA_N.Core.Quantity;

package HRA_N.Core.Event with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Effects_Per_Event : constant := 32;

   subtype Effect_Count_Type is Natural range 0 .. Max_Effects_Per_Event;
   subtype Effect_Index_Type is Positive range 1 .. Max_Effects_Per_Event;

   type Effect is record
      Key     : Effect_Key;
      Locus   : Locus_Id;
      Measure : Measure_Id;
      Amount  : Quantity_Type;
   end record;

   Empty_Effect : constant Effect :=
     (Key     => (Token => (Length => 0, Value => [others => ' '])),
      Locus   => (Token => (Length => 0, Value => [others => ' '])),
      Measure => (Token => (Length => 0, Value => [others => ' '])),
      Amount  => (Quanta => Zero_Quanta));

   type Effect_Array is array (Effect_Index_Type) of Effect;

   type Effect_List is record
      Count  : Effect_Count_Type := 0;
      Values : Effect_Array := [others => Empty_Effect];
   end record;

   -- Nodup specification: no duplicate Effect_Key in the list
   function Keys_Are_Unique (Effects : Effect_List) return Boolean is
     (for all I in 1 .. Effects.Count =>
        (for all J in I + 1 .. Effects.Count =>
           not Equal_Token (Effects.Values (I).Key.Token, Effects.Values (J).Key.Token)));

   type Event is record
      Id      : Event_Id;
      Effects : Effect_List;
   end record;

   function Make_Event
     (Id      : Event_Id;
      Effects : Effect_List) return Event
   with
     Pre  => Keys_Are_Unique (Effects),
     Post => Make_Event'Result.Id = Id
             and then Make_Event'Result.Effects = Effects
             and then Keys_Are_Unique (Make_Event'Result.Effects);

   -- Project net quantity at a given (Locus, Measure) coordinate
   function Quantity_At
     (Ev      : Event;
      Locus   : Locus_Id;
      Measure : Measure_Id) return Long_Long_Integer;

   -- Check if event effects close to zero within one single measure
   function Is_Balanced_Single_Measure
     (Ev      : Event;
      Measure : Measure_Id) return Boolean;

end HRA_N.Core.Event;
