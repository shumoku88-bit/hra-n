------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Publisher
--
--  Atomic publication and mutation operations on canonical journal.hra.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Publisher is

   type Publish_Result is record
      Success      : Boolean := False;
      Event_Id_Str : String (1 .. 64) := [others => ' '];
      Event_Id_Len : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Publish a 2-party movement transaction into journal.hra
   function Publish_Movement
     (Journal_Path : String;
      Policy_Path  : String;
      From_Locus   : String;
      To_Locus     : String;
      Amount       : Quanta_Type;
      Valid_On     : Date_Type;
      Description  : String := "";
      Explicit_Id  : String := "") return Publish_Result;

   --  Publish a reversal transaction into journal.hra
   function Publish_Reversal
     (Journal_Path    : String;
      Target_Event_Id : String;
      Valid_On        : Date_Type;
      Description     : String := "") return Publish_Result;

   --  Publish a correction (reversal + new movement) into journal.hra
   function Publish_Correction
     (Journal_Path    : String;
      Policy_Path     : String;
      Target_Event_Id : String;
      From_Locus      : String;
      To_Locus        : String;
      Amount          : Quanta_Type;
      Valid_On        : Date_Type;
      Description     : String := "") return Publish_Result;

end HRA_N.Application.Publisher;
