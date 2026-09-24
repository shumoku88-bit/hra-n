-------------------------------------------------------------------------------
--  HRA-N: read-only CLI adapter for Loam canonical Actual
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Directories;
use type Ada.Directories.File_Kind;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with HRA_N.Core.Types;       use HRA_N.Core.Types;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Validity;    use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query;        use HRA_N.Application.Actual_Query;
with HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Frontend_Types;       use HRA_N.Application.Frontend_Types;
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

   procedure Display_Detail
     (Path     : String;
      Event_Id : Token_Text;
      Success  : out Boolean)
   is
      use HRA_N.Application.Actual_Detail_Query;
      View : constant Actual_Detail_View :=
        Execute_Loam_Actual (Path, Event_Id);
   begin
      Success := False;

      if View.Status = Query_Rejected then
         Put_Error_Line ("hra-n actual: event not found or rejected");
         if View.Diagnostic_Len > 0 then
            Put_Error_Line
              ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
         end if;
         return;
      end if;

      Put_Line ("============================================================");
      Put_Line (" HRA-N Actual Detail (Loam canonical, read-only)");
      Put_Line
        (" Identity    : " & View.Event_Id.Value (1 .. View.Event_Id.Length));
      Put_Line
        (" Status      : " &
         (if View.Is_Superseded
          then "SUPERSEDED by " & View.Superseded_By.Value (1 .. View.Superseded_By.Length)
          elsif View.Is_Reversed
          then "REVERSED by " & View.Reversed_By.Value (1 .. View.Reversed_By.Length)
          else "ACTIVE"));
      Put_Line
        (" Date        : " &
         (if View.Has_Date then Format_Iso_Date (View.Valid_On) else "UNKNOWN"));
      Put_Line
        (" Description : " &
         (if View.Description.Length = 0
          then "(none)"
          else To_String (View.Description)));
      if View.Has_Purpose then
         Put_Line
           (" Purpose     : " & View.Purpose.Value (1 .. View.Purpose.Length));
      end if;
      if View.Has_Replaces then
         Put_Line
           (" Replaces    : " & View.Replaces.Value (1 .. View.Replaces.Length));
      end if;
      if View.Has_Reverses then
         Put_Line
           (" Reverses    : " & View.Reverses.Value (1 .. View.Reverses.Length));
      end if;
      Put_Line ("------------------------------------------------------------");
      Put_Line (" Effects (" & Trim (View.Effect_Count'Image, Both) & "):");
      for I in 1 .. View.Effect_Count loop
         declare
            Eff     : constant Effect_View := View.Effects (I);
            Loc_Str : constant String := Eff.Locus.Value (1 .. Eff.Locus.Length);
            Mea_Str : constant String := Eff.Measure.Value (1 .. Eff.Measure.Length);
            Amt_Str : constant String := Format_Amount (Eff.Amount);
         begin
            Put_Line ("   " & Pad_Right (Loc_Str, 20) & Pad_Left (Amt_Str, 12) & " " & Mea_Str);
         end;
      end loop;
      Put_Line ("============================================================");

      Success := True;
   end Display_Detail;

   procedure Dispatch
     (Command_Idx      : Positive;
      Rem_Args         : Natural;
      Success          : out Boolean;
      Default_Data_Dir : String := "")
   is
      Default_Day : constant Date_Type := (Year => 2026, Month => 1, Day => 1);

      function Find_Canonical_Actual return String is
      begin
         if Default_Data_Dir'Length > 0 then
            declare
               Candidate : constant String :=
                 Ada.Directories.Compose (Default_Data_Dir, "actual.loam");
            begin
               if Ada.Directories.Exists (Candidate) then
                  return Candidate;
               end if;
            end;
         end if;
         return "";
      end Find_Canonical_Actual;

   begin
      Success := False;

      if Rem_Args = 0 then
         declare
            Path : constant String := Find_Canonical_Actual;
         begin
            if Path'Length = 0 then
               Put_Error_Line
                 ("Usage: hra-n actual [/path/to/actual.loam] [YYYY-MM-DD | <EVENT_ID>]");
               return;
            end if;
            Display
              (Path,
               (Scope        => Scope_All,
                Selected_Day => Default_Day,
                Ordering     => Order_Newest_First),
               Success);
            return;
         end;
      elsif Rem_Args = 1 then
         declare
            Arg1 : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
            Day  : Date_Type;
         begin
            if Ada.Directories.Exists (Arg1)
              and then Ada.Directories.Kind (Arg1) = Ada.Directories.Ordinary_File
            then
               Display
                 (Arg1,
                  (Scope        => Scope_All,
                   Selected_Day => Default_Day,
                   Ordering     => Order_Newest_First),
                  Success);
               return;
            end if;

            declare
               Path : constant String := Find_Canonical_Actual;
            begin
               if Path'Length > 0 then
                  if Parse_Iso_Date (Arg1, Day) then
                     Display
                       (Path,
                        (Scope        => Scope_Selected_Day,
                         Selected_Day => Day,
                         Ordering     => Order_Newest_First),
                        Success);
                     return;
                  else
                     Display_Detail (Path, Make_Token (Arg1), Success);
                     return;
                  end if;
               end if;
            end;

            Put_Error_Line
              ("Usage: hra-n actual [/path/to/actual.loam] [YYYY-MM-DD | <EVENT_ID>]");
            return;
         end;
      elsif Rem_Args = 2 then
         declare
            Path : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
            Arg2 : constant String := Ada.Command_Line.Argument (Command_Idx + 2);
            Day  : Date_Type;
         begin
            if Parse_Iso_Date (Arg2, Day) then
               Display
                 (Path,
                  (Scope        => Scope_Selected_Day,
                   Selected_Day => Day,
                   Ordering     => Order_Newest_First),
                  Success);
            else
               Display_Detail (Path, Make_Token (Arg2), Success);
            end if;
            return;
         end;
      else
         Put_Error_Line
           ("Usage: hra-n actual [/path/to/actual.loam] [YYYY-MM-DD | <EVENT_ID>]");
         return;
      end if;
   end Dispatch;

end HRA_N.UI.Actual_CLI;
