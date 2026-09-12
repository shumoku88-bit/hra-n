-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Record_TUI
--
--  Keyboard-first movement editor opened from Selected Day.
--  Connects typed user input to HRA_N.Application.Movement_Command.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types;
with HRA_N.Core.Validity;

package HRA_N.UI.Record_TUI is

   type Movement_Initial_Values is record
      Target_Id           : HRA_N.Core.Types.Token_Text :=
        (Length => 0, Value => [others => ' ']);
      Target_Scheduled_Id : HRA_N.Core.Types.Token_Text :=
        (Length => 0, Value => [others => ' ']);
      Date                : HRA_N.Core.Validity.Date_Type;
      From_Locus          : HRA_N.Core.Types.Token_Text :=
        (Length => 0, Value => [others => ' ']);
      To_Locus            : HRA_N.Core.Types.Token_Text :=
        (Length => 0, Value => [others => ' ']);
      Amount              : HRA_N.Core.Types.Quanta_Type := 0;
      Description         : HRA_N.Core.Types.Token_Text :=
        (Length => 0, Value => [others => ' ']);
   end record;

   --  Run the keyboard-first movement editor seeded with Selected_Day.
   --  Committed is True if and only if an admitted proposal was committed
   --  to a new immutable generation and activated via CURRENT.
   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean);

   --  Run the keyboard-first correction editor seeded with target details.
   --  Proposes a replacement transaction (replaces:Target_Id).
   --  On success, New_Event_Id holds the newly created replacement event identity.
   procedure Run_Correction
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Init         : Movement_Initial_Values;
      New_Event_Id : out HRA_N.Core.Types.Token_Text;
      Committed    : out Boolean);

   --  Run the keyboard-first split editor.
   procedure Run_Split
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean);

   --  Run the keyboard-first scheduled obligation creation editor.
   procedure Run_Scheduled_Create
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Expected_Day : HRA_N.Core.Validity.Date_Type;
      New_Sched_Id : out HRA_N.Core.Types.Token_Text;
      Committed    : out Boolean);

   --  Run the keyboard-first scheduled completion editor seeded with scheduled details.
   --  Proposes an Actual transaction and marks the obligation completed.
   procedure Run_Scheduled_Complete
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Init         : Movement_Initial_Values;
      New_Event_Id : out HRA_N.Core.Types.Token_Text;
      Committed    : out Boolean);

end HRA_N.UI.Record_TUI;
