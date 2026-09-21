-------------------------------------------------------------------------------
--  HRA-N: read-only CLI adapter for Loam canonical Actual
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Validity;    use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query; use HRA_N.Application.Actual_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Actual_CLI is

   function Row_Text (Item : Actual_Row) return String is
      Date_Text : constant String :=
        (if Item.Has_Date
         then Format_Iso_Date (Item.Valid_On)
         else "DATE-UNKNOWN");
      Id_Text : constant String :=
        Item.Event_Id.Value (1 .. Item.Event_Id.Length);
      Desc_Text : constant String :=
        (if Item.Description.Length = 0
         then "(no description)"
         else To_String (Item.Description));
   begin
      return Date_Text & "  " & Id_Text & "  " & Desc_Text;
   end Row_Text;

   procedure Display
     (Path    : String;
      Request : Query;
      Success : out Boolean)
   is
      View : constant Actual_View := Execute_Loam_Actual (Path, Request);
   begin
      Success := False;

      if View.Status = Query_Rejected then
         Put_Error_Line ("hra-n actual: canonical Actual rejected");
         if View.Diagnostic_Len > 0 then
            Put_Error_Line
              ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
         end if;
         return;
      end if;

      Put_Line ("============================================================");
      Put_Line (" HRA-N Actual (Loam canonical, read-only)");
      if Request.Scope = Scope_Selected_Day then
         Put_Line (" Date   : " & Format_Iso_Date (Request.Selected_Day));
      else
         Put_Line (" Scope  : all admitted Actual");
      end if;
      Put_Line
        (" Order  : " &
         (if Request.Ordering = Order_Newest_First
          then "newest first"
          else "oldest first"));
      Put_Line
        (" Status : " &
         (case View.Status is
            when Query_Complete => "COMPLETE",
            when Query_Partial  => "PARTIAL",
            when Query_Rejected => "REJECTED"));
      Put_Line ("============================================================");

      if View.Row_Count = 0 then
         Put_Line ("  No Actual records in this scope.");
      else
         for I in 1 .. View.Row_Count loop
            Put_Line ("  " & Row_Text (View.Rows (I)));
         end loop;
      end if;

      Put_Line ("------------------------------------------------------------");
      Put_Line
        (" Total: " &
         Trim (View.Row_Count'Image, Both) &
         " Actual records");
      Put_Line ("============================================================");

      if View.Status = Query_Partial and then View.Diagnostic_Len > 0 then
         Put_Error_Line
           ("hra-n actual: " &
            View.Diagnostic (1 .. View.Diagnostic_Len));
      end if;

      Success := True;
   end Display;

   procedure Dispatch
     (Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
      Default_Day : constant Date_Type := (Year => 2026, Month => 1, Day => 1);
   begin
      Success := False;

      if Rem_Args not in 1 .. 2 then
         Put_Error_Line
           ("Usage: hra-n actual /path/to/actual.loam [YYYY-MM-DD]");
         return;
      end if;

      declare
         Path : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
      begin
         if Rem_Args = 1 then
            Display
              (Path,
               (Scope        => Scope_All,
                Selected_Day => Default_Day,
                Ordering     => Order_Newest_First),
               Success);
         else
            declare
               Date_Arg : constant String :=
                 Ada.Command_Line.Argument (Command_Idx + 2);
               Day : Date_Type;
            begin
               if not Parse_Iso_Date (Date_Arg, Day) then
                  Put_Error_Line
                    ("hra-n actual: date must be a real YYYY-MM-DD calendar date");
                  return;
               end if;

               Display
                 (Path,
                  (Scope        => Scope_Selected_Day,
                   Selected_Day => Day,
                   Ordering     => Order_Newest_First),
                  Success);
            end;
         end if;
      end;
   end Dispatch;

end HRA_N.UI.Actual_CLI;
