-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Boundary_Presets_Reader
--
--  Parses config/boundary-presets.tsv into verified budget window presets.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Storage.Boundary_Presets_Reader is

   Max_Presets : constant := 16;

   type Boundary_Preset is record
      Name       : Token_Text;
      Start_Year : Natural;
      Start_Month: Natural;
      Start_Day  : Natural;
      End_Year   : Natural;
      End_Month  : Natural;
      End_Day    : Natural;
   end record;

   Empty_Preset : constant Boundary_Preset :=
     (Name        => (Length => 0, Value => [others => ' ']),
      Start_Year  => 0,
      Start_Month => 0,
      Start_Day   => 0,
      End_Year    => 0,
      End_Month   => 0,
      End_Day     => 0);

   subtype Preset_Count_Type is Natural range 0 .. Max_Presets;
   subtype Preset_Index_Type is Positive range 1 .. Max_Presets;
   type Preset_Array is array (Preset_Index_Type) of Boundary_Preset;

   type Presets_Memory is record
      Count   : Preset_Count_Type := 0;
      Presets : Preset_Array      := [others => Empty_Preset];
   end record;

   type Read_Result is record
      Success      : Boolean          := False;
      Memory       : Presets_Memory;
      Error_Line   : Natural          := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural          := 0;
   end record;

   function Read_Boundary_Presets_File (Path : String) return Read_Result;

   function Find_Preset
     (Mem    : Presets_Memory;
      Name   : String;
      Preset : out Boundary_Preset) return Boolean;

end HRA_N.Storage.Boundary_Presets_Reader;
