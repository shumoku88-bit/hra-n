-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core.Window_Policy
--
--  Budget and Evaluation Window policy facts.
--  Windows define half-open calendar intervals [Start_Date, End_Date).
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Core.Window_Policy with
  SPARK_Mode => On
is
   pragma Pure;

   Max_Windows : constant := 64;

   subtype Window_Count_Type is Natural range 0 .. Max_Windows;
   subtype Window_Index_Type is Positive range 1 .. Max_Windows;

   type Window_Definition is record
      Id         : Token_Text;
      Start_Date : Date_Type;
      End_Date   : Date_Type;
      Name       : Token_Text;
   end record;

   Empty_Window : constant Window_Definition :=
     (Id         => (Length => 0, Value => [others => ' ']),
      Start_Date => (Year => 2026, Month => 1, Day => 1),
      End_Date   => (Year => 2026, Month => 1, Day => 2),
      Name       => (Length => 0, Value => [others => ' ']));

   type Window_Array is array (Window_Index_Type) of Window_Definition;

   type Window_Memory is record
      Count   : Window_Count_Type := 0;
      Windows : Window_Array      := [others => Empty_Window];
   end record;

   function Date_In_Window
     (D   : Date_Type;
      Win : Window_Definition) return Boolean is
     (Date_Less_Or_Equal (Win.Start_Date, D)
      and then Date_Less (D, Win.End_Date));

   function Windows_Are_Sound (Mem : Window_Memory) return Boolean is
     ((for all I in 1 .. Mem.Count =>
         Mem.Windows (I).Id.Length > 0
         and then Date_Less (Mem.Windows (I).Start_Date, Mem.Windows (I).End_Date)
         and then (for all J in I + 1 .. Mem.Count =>
                     not Equal_Token (Mem.Windows (I).Id, Mem.Windows (J).Id))));

   procedure Find_Window_By_Id
     (Mem   : Window_Memory;
      Id    : Token_Text;
      Win   : out Window_Definition;
      Found : out Boolean);

   procedure Find_Window_For_Date
     (Mem   : Window_Memory;
      D     : Date_Type;
      Win   : out Window_Definition;
      Found : out Boolean);

   function Window_Count (Mem : Window_Memory) return Window_Count_Type is
     (Mem.Count);

   function Window_At
     (Mem   : Window_Memory;
      Index : Window_Index_Type) return Window_Definition
   with
     Pre => Index <= Mem.Count;

end HRA_N.Core.Window_Policy;
