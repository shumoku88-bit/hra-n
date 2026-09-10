-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Publisher
--
--  Authority publication boundary for recording verified Movements.
--  Coordinates writer ownership, content-addressed persistence, and CURRENT update.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Publisher is

   type Publish_Result is record
      Success      : Boolean             := False;
      Event_Id_Str : String (1 .. 64)    := [others => ' '];
      Event_Id_Len : Natural             := 0;
      Error_Reason : String (1 .. 128)   := [others => ' '];
      Error_Len    : Natural             := 0;
   end record;

   --  Publish a balanced two-party movement into the selected authority.
   --  From_Locus decreases by Amount (-Amount), To_Locus increases by Amount (+Amount).
   function Publish_Movement
     (Authority_Dir : String;
      From_Locus    : String;
      To_Locus      : String;
      Amount        : Quanta_Type;
      Valid_On      : Date_Type;
      Description   : String := "";
      Explicit_Id   : String := "") return Publish_Result;

   --  Publish an exact inverse reversal event canceling a previous movement.
   --  Optionally synchronizes with LOAM-ACTUAL-REVERSAL-MEMORY file.
   function Publish_Reversal
     (Authority_Dir   : String;
      Target_Event_Id : String;
      Valid_On        : Date_Type;
      Description     : String := "";
      Reversals_Path  : String := "") return Publish_Result;

end HRA_N.Application.Publisher;
