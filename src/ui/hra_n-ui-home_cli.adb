-------------------------------------------------------------------------------
--  HRA-N: one-shot renderer for the shared Home query
-------------------------------------------------------------------------------

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Home_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Snapshot_Label;

package body HRA_N.UI.Home_CLI is

   function Image (Value : Natural) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   procedure Display_Home
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Success : out Boolean)
   is
      Today : constant Date_Type := Get_System_Date;
      View  : constant HRA_N.Application.Home_Query.Home_View :=
        HRA_N.Application.Home_Query.Execute
          (Paths,
           (Selected_Day => Today));
   begin
      Success := False;

      if View.Status = Query_Rejected then
         Put_Error_Line
           ("hra-n: " & View.Diagnostic (1 .. View.Diagnostic_Len));
         return;
      end if;

      Put_Line ("HRA-N Home  " & Format_Iso_Date (View.Selected_Day));
      Put_Line ("------------------------------------------------------------");
      if View.Status = Query_Complete then
         Put_Line ("Evidence    COMPLETE");
      else
         Put_Line ("Evidence    PARTIAL");
      end if;
      Put_Line ("Actual      " & Image (View.Selected_Actual) & " selected / " &
                Image (View.Total_Actual) & " total");
      Put_Line ("Scheduled   " & Image (View.Selected_Scheduled) & " selected / " &
                Image (View.Open_Scheduled) & " open / " &
                Image (View.Total_Scheduled) & " retained");
      Put_Line ("Policy      " & Image (View.Role_Assignments) & " roles / " &
                Image (View.Zero_Origins) & " zero origins");
      if View.Open_Attentions > 0 then
         Put_Line ("Attention   " & Image (View.Open_Attentions) & " open" &
                   (if View.Unresolved_Loci > 0
                    then " / " & Image (View.Unresolved_Loci) & " unclassified loci"
                    else ""));
      elsif View.Unresolved_Loci > 0 then
         Put_Line ("Attention   " & Image (View.Unresolved_Loci) &
                   " unclassified loci");
      else
         Put_Line ("Attention   none from this projection");
      end if;
      Put_Line ("Snapshot    " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
      Put_Line ("------------------------------------------------------------");
      Put_Line ("Use explicit commands for current write operations.");

      Success := True;
   end Display_Home;

end HRA_N.UI.Home_CLI;
