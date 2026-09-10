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

   type Relation_Direction is
     (External_To_Household, Household_To_External);

   type Relation_Publish_Result is record
      Success      : Boolean           := False;
      Relation_Id  : String (1 .. 64) := [others => ' '];
      Id_Len       : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

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

   function Publish_Relation_Unit
     (Authority_Dir : String;
      Source_Event  : String;
      Source_Effect : String;
      Direction     : Relation_Direction;
      External_Id   : String;
      Quantity      : Quanta_Type;
      Explicit_Id   : String := "") return Relation_Publish_Result;

   --  Attach exact discharge evidence to an already-published later Event.
   --  Missing Events are rejected by this interactive publication boundary;
   --  pre-Event residue remains supported by the raw reader/frontier.
   function Publish_Relation_Discharge
     (Authority_Dir : String;
      Event_Id      : String;
      Target_Id     : String;
      Quantity      : Quanta_Type) return Relation_Publish_Result;

end HRA_N.Application.Publisher;
