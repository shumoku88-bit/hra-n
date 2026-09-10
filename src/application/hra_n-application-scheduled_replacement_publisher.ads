-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Scheduled_Replacement_Publisher
--
--  Coordinates explicit Scheduled replacement publication under strict
--  two-phase lock ownership:
--    Scheduled lifecycle lock -> Movement manifest lock
-------------------------------------------------------------------------------

with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Application.Scheduled_Replacement_Publisher is

   type Replacement_Draft is record
      Source       : Scheduled_Id;
      Scheduled_On : Date_Type;
      From_Locus   : String (1 .. 64) := [others => ' '];
      From_Len     : Natural          := 0;
      To_Locus     : String (1 .. 64) := [others => ' '];
      To_Len       : Natural          := 0;
      Amount       : Quanta_Type      := 0;
      Measure      : Measure_Id       := (Token => (Length => 0, Value => [others => ' ']));
   end record;

   function Make_Two_Party_Draft
     (Source      : String;
      From_Locus  : String;
      To_Locus    : String;
      Amount      : Quanta_Type;
      Valid_On    : Date_Type;
      Measure_Str : String := "jpy") return Replacement_Draft;

   type Replacement_Receipt is record
      Success      : Boolean             := False;
      Source       : Scheduled_Id;
      Replacement  : Scheduled_Id;
      Scheduled_On : Date_Type;
      Amount       : Quanta_Type         := 0;
      Error_Reason : String (1 .. 128)   := [others => ' '];
      Error_Len    : Natural             := 0;
   end record;

   --  Replace one current-open Scheduled occurrence under writer ownership.
   --  Fixed ownership order: Scheduled lifecycle lock -> Movement manifest lock.
   function Publish_Replacement
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Draft          : Replacement_Draft) return Replacement_Receipt;

end HRA_N.Application.Scheduled_Replacement_Publisher;
