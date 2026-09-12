with HRA_N.Application.Path_Resolver;
with HRA_N.Application.Actual_Detail_Query;
with HRA_N.Core.Types;

package HRA_N.UI.Date_Correction_TUI is

   --  Run the focused date-only correction editor for an active Actual movement.
   --  Preserves loci, amounts, and description while superseding the transaction
   --  with an updated canonical date.
   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Detail       : HRA_N.Application.Actual_Detail_Query.Actual_Detail_View;
      New_Event_Id : out HRA_N.Core.Types.Token_Text;
      Committed    : out Boolean);

end HRA_N.UI.Date_Correction_TUI;
