-------------------------------------------------------------------------------
--  HRA-N: Attention CLI (read-only canonical observation)
-------------------------------------------------------------------------------

with HRA_N.Application.Attention_Query; use HRA_N.Application.Attention_Query;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Attention_CLI is

   procedure Display_Attention (Paths : Path_Config; Success : out Boolean) is
      View : constant Attention_View := Execute (Paths);
   begin
      Success := View.Success;
      if not View.Success then
         Put_Line ("[ERROR] " & View.Diagnostic (1 .. View.Diagnostic_Len));
         return;
      end if;
      if View.Availability = Attention_Unavailable then
         Put_Line ("Attention unavailable");
         return;
      end if;
      Put_Line ("============================================================");
      Put_Line (" HRA-N Attention (" & Natural'Image (View.Count) & " open)");
      Put_Line ("============================================================");
      for I in 1 .. View.Count loop
         Put_Line
           ("  " & View.Rows (I).Id.Value (1 .. View.Rows (I).Id.Length)
            & "  [" & Due_Label (View.Rows (I).Due) & "]  "
            & View.Rows (I).Context.Value (1 .. View.Rows (I).Context.Length));
      end loop;
   end Display_Attention;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
      pragma Unreferenced (Command_Idx);
   begin
      if Rem_Args = 0 then
         Display_Attention (Paths, Success);
      else
         Success := False;
         Put_Line ("[ERROR] canonical Attention mutation is not implemented by HRA-N; legacy mutation removed");
      end if;
   end Dispatch;

end HRA_N.UI.Attention_CLI;
