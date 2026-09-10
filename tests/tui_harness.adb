with Ada.Command_Line;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Home_TUI;

procedure TUI_Harness is
   Success : Boolean := False;
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   HRA_N.UI.Home_TUI.Run
     (Paths   => Resolve_Paths (Ada.Command_Line.Argument (1)),
      Success => Success);

   if not Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end TUI_Harness;
