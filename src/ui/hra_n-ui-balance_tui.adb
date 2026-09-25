-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Balance_TUI
-------------------------------------------------------------------------------

with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Application.Balance_Query; use HRA_N.Application.Balance_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Balance_TUI is

   package Curses renames Terminal_Interface.Curses;

   function Status_Badge (Status : Balance_Epistemic_Status) return String is
     (case Status is
        when Status_Known_Zero      => "KNOWN ZERO",
        when Status_Unknown_Origin  => "UNKNOWN   ",
        when Status_Conflict        => "CONFLICT  ");

   function Role_Badge (Row : Balance_Row) return String is
   begin
      if not Row.Has_Role then
         return "(none)   ";
      end if;
      return (case Row.Role is
                when Role_Asset     => "ASSET    ",
                when Role_Liability => "LIABILITY",
                when Role_Equity    => "EQUITY   ",
                when Role_Income    => "INCOME   ",
                when Role_Expense   => "EXPENSE  ");
   end Role_Badge;

   function Row_Text (Row : Balance_Row) return String is
      Loc_Str   : constant String := Row.Locus.Value (1 .. Row.Locus.Length);
      Mea_Str   : constant String := Row.Measure.Value (1 .. Row.Measure.Length);
      Amt_Str   : constant String := Format_Amount (Quanta_Type (Row.Amount));
      Posts_Str : constant String := Trim (Row.Posting_Count'Image, Ada.Strings.Both);
   begin
      return Status_Badge (Row.Epistemic_Status) & "  " &
             Role_Badge (Row) & "  " &
             Pad_Right (Loc_Str, 14) & " " &
             Pad_Right (Mea_Str, 8) & " " &
             Pad_Left (Amt_Str, 14) & "  " &
             Pad_Left (Posts_Str, 6);
   end Row_Text;

   procedure Draw
     (View   : Balance_View;
      Cursor : Positive;
      Count  : out Natural)
   is
      Capacity : constant Natural := (if Rows > 8 then Rows - 8 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
      Scope_Label : constant String :=
        (case View.Scope is
           when Scope_All          => "ALL",
           when Scope_Known_Only   => "KNOWN ZERO",
           when Scope_Unknown_Only => "UNKNOWN ORIGIN");
   begin
      Curses.Erase;
      HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
      Put_Clipped
        (0,
         "HRA-N BALANCES  " & Scope_Label &
         (if View.Has_As_Of then " (as-of " & Format_Iso_Date (View.As_Of_Date) & ")" else ""));
      HRA_N.UI.Terminal_Style.Reset;
      Put_Clipped (1, "============================================================");

      Count := Natural (View.Row_Count);
      if View.Status = Query_Rejected then
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
         Put_Clipped (3, "AUTHORITY REJECTED");
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      elsif Count = 0 then
         Put_Clipped (3, "No coordinate balances in this scope.");
      else
         Put_Clipped (3, "  STATUS      ROLE       LOCUS          MEASURE       AMOUNT      POSTS");
         Put_Clipped (4, " ----------------------------------------------------------------------");
         if Capacity > 0 then
            if Cursor > Capacity then
               First := Cursor - Capacity + 1;
            end if;
            Last := Natural'Min (Count, First + Capacity - 1);
            for Index in First .. Last loop
               if Index = Cursor then
                  HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
                  Put_Clipped
                    (5 + Index - First,
                     "> " & Row_Text (View.Rows (Index)));
                  HRA_N.UI.Terminal_Style.Reset;
               else
                  Put_Clipped
                    (5 + Index - First,
                     "  " & Row_Text (View.Rows (Index)));
               end if;
            end loop;
         end if;
      end if;

      if Rows > 3 and then View.Status = Query_Partial then
         Put_Clipped (Rows - 3, View.Diagnostic (1 .. View.Diagnostic_Len));
      end if;
      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            (if View.Source = Canonical_Balance
             then "canonical balances: read-only   f: scope   t: as-of   b/Esc/q: home"
             else "j/k/wheel: select   f: scope   t: toggle as-of   b/Esc/q: home"));
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : HRA_N.Core.Validity.Date_Type;
      Initial_Scope : HRA_N.Application.Balance_Query.Balance_Scope :=
        HRA_N.Application.Balance_Query.Scope_All)
   is
      Current_Paths   : Path_Config := Paths;
      Scope           : Balance_Scope := Initial_Scope;
      Filter_As_Of    : Boolean := False;
      Cursor          : Positive := 1;
      Count           : Natural := 0;
      Running         : Boolean := True;
      Current_View    : Balance_View;

      procedure Reload is
      begin
         Current_View := HRA_N.Application.Balance_Query.Execute
           (Current_Paths,
            (Scope => Scope, Has_As_Of => Filter_As_Of, As_Of_Date => Selected_Day));
      end Reload;
   begin
      HRA_N.UI.Terminal_Style.Initialize;
      HRA_N.UI.TUI_Input.Start_Mouse_Scroll;

      Reload;

      while Running loop
         Draw (Current_View, Cursor, Count);
         if Count = 0 then
            Cursor := 1;
         elsif Cursor > Count then
            Cursor := Positive (Count);
         end if;

         declare
            Evt : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
         begin
            case Evt.Kind is
               when HRA_N.UI.TUI_Input.Scroll_Input =>
                  case Evt.Direction is
                     when HRA_N.UI.TUI_Input.Scroll_Up =>
                        if Cursor > 1 then
                           Cursor := Cursor - 1;
                        end if;
                     when HRA_N.UI.TUI_Input.Scroll_Down =>
                        if Cursor < Count then
                           Cursor := Cursor + 1;
                        end if;
                  end case;

               when HRA_N.UI.TUI_Input.Key_Input =>
                  declare
                     Key : constant Integer := Evt.Key_Code;
                  begin
                     if HRA_N.UI.TUI_Input.Is_Quit (Key)
                       or else Key = Character'Pos ('b')
                       or else Key = Character'Pos ('B')
                     then
                        Running := False;
                     elsif HRA_N.UI.TUI_Input.Is_Down (Key) then
                        if Count > 0 and then Cursor < Count then
                           Cursor := Cursor + 1;
                        end if;
                     elsif HRA_N.UI.TUI_Input.Is_Up (Key) then
                        if Cursor > 1 then
                           Cursor := Cursor - 1;
                        end if;
                     elsif Key = Integer (Curses.KEY_NPAGE)
                       or else Key = 4
                       or else Key = 32
                     then
                        declare
                           Step : constant Positive :=
                             Positive'Max (1, (if Rows > 8 then Rows - 8 else 5));
                        begin
                           Cursor := (if Count > 0 then Natural'Min (Count, Cursor + Step) else 1);
                        end;
                     elsif Key = Integer (Curses.KEY_PPAGE)
                       or else Key = 21
                     then
                        declare
                           Step : constant Positive :=
                             Positive'Max (1, (if Rows > 8 then Rows - 8 else 5));
                        begin
                           Cursor := (if Cursor > Step then Cursor - Step else 1);
                        end;
                     elsif Key = Character'Pos ('G') then
                        if Count > 0 then
                           Cursor := Count;
                        end if;
                     elsif Key = Character'Pos ('g') then
                        Cursor := 1;
                     elsif Key = Character'Pos ('f') or else Key = Character'Pos ('F') then
                        Scope :=
                          (case Scope is
                             when Scope_All          => Scope_Known_Only,
                             when Scope_Known_Only   => Scope_Unknown_Only,
                             when Scope_Unknown_Only => Scope_All);
                        Cursor := 1;
                        Reload;
                     elsif Key = Character'Pos ('t') or else Key = Character'Pos ('T') then
                        Filter_As_Of := not Filter_As_Of;
                        Cursor := 1;
                        Reload;
                     elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                       or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                     then
                        Current_Paths :=
                          HRA_N.Application.Path_Resolver.Resolve_Paths
                            (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                        Reload;
                     end if;
                  end;

               when HRA_N.UI.TUI_Input.Ignored_Input =>
                  null;
            end case;
         end;
      end loop;
   end Run;

end HRA_N.UI.Balance_TUI;
