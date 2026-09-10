-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Validity
--
--  Occurrence-valid date coordinate evidence linking EventId to calendar time.
--
--  Design Rationale (derived from Loam Observation 111 & Architecture):
--  Events themselves remain strictly timeless (neutral identity and effects).
--  Occurrence dates are independently observable validity facts.
--  Each EventId has at most one valid occurrence date (Nodup invariant).
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Core.Validity with
  SPARK_Mode => On
is
   pragma Pure;

   ----------------------------------------------------------------------------
   --  Calendar Date Types & Verified Arithmetic
   ----------------------------------------------------------------------------

   subtype Year_Type  is Integer range 1900 .. 2100;
   subtype Month_Type is Integer range 1 .. 12;
   subtype Day_Type   is Integer range 1 .. 31;

   --  Gregorian leap-year predicate.
   function Is_Leap_Year (Year : Year_Type) return Boolean is
     ((Year mod 400 = 0) or else (Year mod 4 = 0 and then Year mod 100 /= 0));

   --  Exact number of days in a given calendar month.
   function Days_In_Month
     (Year  : Year_Type;
      Month : Month_Type) return Day_Type is
     (case Month is
        when 1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        when 4 | 6 | 9 | 11              => 30,
        when 2                           => (if Is_Leap_Year (Year) then 29 else 28));

   --  Valid calendar date predicate.
   function Is_Valid_Date
     (Year  : Year_Type;
      Month : Month_Type;
      Day   : Day_Type) return Boolean is
     (Day <= Days_In_Month (Year, Month));

   --  Validated calendar date record.
   type Date_Type is record
      Year  : Year_Type  := 2026;
      Month : Month_Type := 1;
      Day   : Day_Type   := 1;
   end record;

   function Make_Date
     (Year  : Year_Type;
      Month : Month_Type;
      Day   : Day_Type) return Date_Type
   with
     Pre => Is_Valid_Date (Year, Month, Day);

   function Equal_Date (Left, Right : Date_Type) return Boolean is
     (Left.Year = Right.Year
      and then Left.Month = Right.Month
      and then Left.Day = Right.Day);

   function Date_Less (Left, Right : Date_Type) return Boolean is
     (Left.Year < Right.Year
      or else (Left.Year = Right.Year and then Left.Month < Right.Month)
      or else (Left.Year = Right.Year
               and then Left.Month = Right.Month
               and then Left.Day < Right.Day));

   function Date_Greater (Left, Right : Date_Type) return Boolean is
     (Right.Year < Left.Year
      or else (Right.Year = Left.Year and then Right.Month < Left.Month)
      or else (Right.Year = Left.Year
               and then Right.Month = Left.Month
               and then Right.Day < Left.Day));

   function Date_Less_Or_Equal (Left, Right : Date_Type) return Boolean is
     (Date_Less (Left, Right) or else Equal_Date (Left, Right));

   function Date_Greater_Or_Equal (Left, Right : Date_Type) return Boolean is
     (Date_Greater (Left, Right) or else Equal_Date (Left, Right));

   --  Calendar date successor (next calendar day).
   function Next_Day (D : Date_Type) return Date_Type is
     (if D.Day < Days_In_Month (D.Year, D.Month) then
        (Year => D.Year, Month => D.Month, Day => D.Day + 1)
      elsif D.Month < 12 then
        (Year => D.Year, Month => D.Month + 1, Day => 1)
      else
        (Year => D.Year + 1, Month => 1, Day => 1))
   with
     Pre  => Is_Valid_Date (D.Year, D.Month, D.Day)
             and then (D.Year < Year_Type'Last or else D.Month < 12 or else D.Day < 31),
     Post => Is_Valid_Date (Next_Day'Result.Year, Next_Day'Result.Month, Next_Day'Result.Day);

   --  Calendar date predecessor (previous calendar day).
   function Prev_Day (D : Date_Type) return Date_Type is
     (if D.Day > 1 then
        (Year => D.Year, Month => D.Month, Day => D.Day - 1)
      elsif D.Month > 1 then
        (Year => D.Year, Month => D.Month - 1, Day => Days_In_Month (D.Year, D.Month - 1))
      else
        (Year => D.Year - 1, Month => 12, Day => 31))
   with
     Pre  => Is_Valid_Date (D.Year, D.Month, D.Day)
             and then (D.Year > Year_Type'First or else D.Month > 1 or else D.Day > 1),
     Post => Is_Valid_Date (Prev_Day'Result.Year, Prev_Day'Result.Month, Prev_Day'Result.Day);

   --  7 consecutive calendar days ending at the specified date (D-6 .. D).
   type Week_Days_Array is array (1 .. 7) of Date_Type;

   function Previous_Days_7 (Ending : Date_Type) return Week_Days_Array
   with
     Pre  => Is_Valid_Date (Ending.Year, Ending.Month, Ending.Day)
             and then Ending.Year > Year_Type'First,
     Post => (for all I in 1 .. 7 =>
                Is_Valid_Date (Previous_Days_7'Result (I).Year,
                               Previous_Days_7'Result (I).Month,
                               Previous_Days_7'Result (I).Day));

   subtype Iso_Date_String is String (1 .. 10);

   --  Format Date_Type as ISO YYYY-MM-DD string.
   function Format_Iso_Date (D : Date_Type) return Iso_Date_String;

   ----------------------------------------------------------------------------
   --  Actual Validity Evidence
   ----------------------------------------------------------------------------

   --  One atomic claim that an event occurred on a specific calendar date.
   type Validity_Entry is record
      Event_Id : Types.Event_Id;
      Valid_On : Date_Type;
   end record;

   Max_Validity_Entries : constant := 1024;

   subtype Validity_Count_Type is Natural range 0 .. Max_Validity_Entries;
   subtype Validity_Index_Type is Positive range 1 .. Max_Validity_Entries;

   type Validity_Array is array (Validity_Index_Type) of Validity_Entry;

   type Validity_Entry_List is record
      Count  : Validity_Count_Type := 0;
      Values : Validity_Array      := [others =>
                 (Event_Id => (Token => (Length => 0, Value => [others => ' '])),
                  Valid_On => (Year => 2026, Month => 1, Day => 1))];
   end record;

   --  Specification invariant: each EventId has at most one valid date entry.
   function Event_Ids_Are_Unique (Entries : Validity_Entry_List) return Boolean is
     (for all I in 1 .. Entries.Count =>
        (for all J in I + 1 .. Entries.Count =>
           not Equal_Token (Entries.Values (I).Event_Id.Token,
                            Entries.Values (J).Event_Id.Token)));

   --  Encapsulated validity memory instance.
   type Validity_Memory is private;

   function Make_Validity_Memory
     (Entries : Validity_Entry_List) return Validity_Memory
   with
     Pre => Event_Ids_Are_Unique (Entries);

   function Entry_Count (Memory : Validity_Memory) return Validity_Count_Type;

   function Entry_At
     (Memory : Validity_Memory;
      Index  : Validity_Index_Type) return Validity_Entry
   with
     Pre => Index <= Entry_Count (Memory);

   --  Look up the occurrence date of a given EventId.
   procedure Find_Occurrence_Date
     (Memory : in  Validity_Memory;
      Ev_Id  : in  Types.Event_Id;
      Date   : out Date_Type;
      Found  : out Boolean);

   ----------------------------------------------------------------------------
   --  Actual Validity History & Correction Types
   ----------------------------------------------------------------------------

   type Validity_Fact_Id is record
      Token : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   type Validity_Correction_Id is record
      Token : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   type Validity_Fact is record
      Id       : Validity_Fact_Id := (Token => (Length => 0, Value => [others => ' ']));
      Event_Id : Types.Event_Id   := (Token => (Length => 0, Value => [others => ' ']));
      Valid_On : Date_Type        := (Year => 2026, Month => 1, Day => 1);
   end record;

   type Validity_Correction is record
      Id          : Validity_Correction_Id := (Token => (Length => 0, Value => [others => ' ']));
      Target      : Validity_Fact_Id       := (Token => (Length => 0, Value => [others => ' ']));
      Replacement : Validity_Fact_Id       := (Token => (Length => 0, Value => [others => ' ']));
   end record;

   Max_Validity_Facts       : constant := 1024;
   Max_Validity_Corrections : constant := 512;

   subtype Validity_Fact_Count is Natural range 0 .. Max_Validity_Facts;
   subtype Validity_Fact_Index is Positive range 1 .. Max_Validity_Facts;

   subtype Validity_Correction_Count is Natural range 0 .. Max_Validity_Corrections;
   subtype Validity_Correction_Index is Positive range 1 .. Max_Validity_Corrections;

   type Fact_Array is array (Validity_Fact_Index) of Validity_Fact;
   type Validity_Correction_Array is array (Validity_Correction_Index) of Validity_Correction;

   type Validity_History is record
      Fact_Count       : Validity_Fact_Count       := 0;
      Facts            : Fact_Array                := [others =>
        (Id       => (Token => (Length => 0, Value => [others => ' '])),
         Event_Id => (Token => (Length => 0, Value => [others => ' '])),
         Valid_On => (Year => 2026, Month => 1, Day => 1))];
      Correction_Count : Validity_Correction_Count := 0;
      Corrections      : Validity_Correction_Array := [others =>
        (Id          => (Token => (Length => 0, Value => [others => ' '])),
         Target      => (Token => (Length => 0, Value => [others => ' '])),
         Replacement => (Token => (Length => 0, Value => [others => ' '])))];
   end record;

   function Root_Fact_Id (Ev_Id : Event_Id) return Validity_Fact_Id;
   function Is_Root_Fact (Fact : Validity_Fact) return Boolean;

   function Fact_Ids_Are_Unique (History : Validity_History) return Boolean is
     (for all I in 1 .. History.Fact_Count =>
        (for all J in I + 1 .. History.Fact_Count =>
           not Equal_Token (History.Facts (I).Id.Token,
                            History.Facts (J).Id.Token)));

   function Correction_Ids_Are_Unique (History : Validity_History) return Boolean is
     (for all I in 1 .. History.Correction_Count =>
        (for all J in I + 1 .. History.Correction_Count =>
           not Equal_Token (History.Corrections (I).Id.Token,
                            History.Corrections (J).Id.Token)));

   procedure Find_Fact_By_Id
     (History : in  Validity_History;
      Id      : in  Validity_Fact_Id;
      Fact    : out Validity_Fact;
      Found   : out Boolean);

   procedure Find_Correction_By_Id
     (History : in  Validity_History;
      Id      : in  Validity_Correction_Id;
      Corr    : out Validity_Correction;
      Found   : out Boolean);

private

   type Validity_Memory is record
      Entries : Validity_Entry_List;
   end record;

   function Entry_Count (Memory : Validity_Memory) return Validity_Count_Type is
     (Memory.Entries.Count);

   function Entry_At
     (Memory : Validity_Memory;
      Index  : Validity_Index_Type) return Validity_Entry is
     (Memory.Entries.Values (Index));

end HRA_N.Core.Validity;
