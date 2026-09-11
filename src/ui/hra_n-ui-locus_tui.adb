-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Locus_TUI
-------------------------------------------------------------------------------

with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Policy_Command; use HRA_N.Application.Policy_Command;
with HRA_N.Application.Policy_Query;   use HRA_N.Application.Policy_Query;
with HRA_N.Application.Proposal;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.UI.Line_Edit;               use HRA_N.UI.Line_Edit;
with HRA_N.UI.Terminal;                use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.TUI_Input;
with Terminal_Interface.Curses;

package body HRA_N.UI.Locus_TUI is

   package Curses renames Terminal_Interface.Curses;

   procedure Run_Add
     (Paths     : Path_Config;
      Committed : out Boolean)
   is
      Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
      Text : constant String :=
        Prompt_For (Prompt_Row, "New stable Locus token: ");
   begin
      Committed := False;
      if Text'Length = 0 then
         return;
      elsif Text'Length > Max_Token_Length then
         Wait_Key (Prompt_Row, "Locus token is too long.");
         return;
      end if;

      declare
         Intent : constant Locus_Intent :=
           (Locus => (Token => Make_Token (Text)));
         Proposed : constant Proposal_Result := Propose_Locus (Paths, Intent);
      begin
         if not Proposed.Success then
            Wait_Key
              (Prompt_Row,
               "Locus admission rejected: "
               & Proposed.Error (1 .. Proposed.Error_Len));
            return;
         end if;
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped (0, "LOCUS ADMISSION PREVIEW  " & Text);
         HRA_N.UI.Terminal_Style.Reset;
         Put_Clipped (1, "============================================================");
         Put_Clipped (3, "Stable token  " & Text);
         Put_Clipped (4, "Permission    new quantity writes");
         Put_Clipped
           (5, "Snapshot      "
            & HRA_N.Application.Proposal.Expected_Snapshot
              (Proposed.Proposal));
         Put_Clipped
           (7, "No role, route, label, alias, or historical rewrite is created.");
         if not Confirm (Prompt_Row, "Admit this Locus?") then
            return;
         end if;
         declare
            Receipt : constant Policy_Receipt := Commit (Proposed.Proposal);
         begin
            if Receipt.Success then
               Committed := True;
            else
               Wait_Key
                 (Prompt_Row,
                  "Locus admission commit rejected: "
                  & Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
   end Run_Add;

   procedure Draw
     (Paths  : Path_Config;
      Scroll : Natural;
      Count  : out Natural)
   is
      View : constant Locus_View := Execute_Locus_Query (Paths);
      Capacity : constant Natural := (if Rows > 7 then Rows - 7 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
      Put_Clipped (0, "LOCUS NEW-WRITE ADMISSION");
      HRA_N.UI.Terminal_Style.Reset;
      Put_Clipped (1, "============================================================");
      Count := View.Row_Count;
      if View.Status = Query_Rejected then
         if View.Diagnostic_Len > 0 then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped
              (3, "! " & View.Diagnostic (1 .. View.Diagnostic_Len));
            HRA_N.UI.Terminal_Style.Reset;
         end if;
      elsif View.Row_Count = 0 then
         Put_Clipped (3, "No Loci are admitted for new quantity writes.");
      else
         Put_Clipped
           (3, "Admitted stable identities (" & View.Row_Count'Image & ")");
         if Capacity > 0 and then View.Row_Count > 0 then
            First := Natural'Min (Scroll + 1, View.Row_Count);
            Last := Natural'Min (View.Row_Count, First + Capacity - 1);
            for I in First .. Last loop
               Put_Clipped
                 (4 + I - First,
                  "  " & View.Rows (I).Value (1 .. View.Rows (I).Length));
            end loop;
         end if;
         if Rows > 3 then
            Put_Clipped
              (Rows - 3,
               "Snapshot: " & View.Snapshot (1 .. View.Snapshot_Len));
         end if;
      end if;
      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "j/k/wheel: scroll  n: admit new Locus  R: reload  b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run (Paths : Path_Config) is
      Current_Paths : Path_Config := Paths;
      Scroll        : Natural := 0;
      Count         : Natural := 0;
      Running       : Boolean := True;
   begin
      HRA_N.UI.Terminal_Style.Initialize;
      HRA_N.UI.TUI_Input.Start_Mouse_Scroll;

      while Running loop
         Draw (Current_Paths, Scroll, Count);
         declare
            Capacity : constant Natural := (if Rows > 7 then Rows - 7 else 5);
            Evt      : constant HRA_N.UI.TUI_Input.Event := HRA_N.UI.TUI_Input.Read;
         begin
            case Evt.Kind is
               when HRA_N.UI.TUI_Input.Scroll_Input =>
                  case Evt.Direction is
                     when HRA_N.UI.TUI_Input.Scroll_Up =>
                        if Scroll > 0 then
                           Scroll := Scroll - 1;
                        end if;
                     when HRA_N.UI.TUI_Input.Scroll_Down =>
                        if Count > Capacity and then Scroll + Capacity < Count then
                           Scroll := Scroll + 1;
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
                        if Count > Capacity and then Scroll + Capacity < Count then
                           Scroll := Scroll + 1;
                        end if;
                     elsif HRA_N.UI.TUI_Input.Is_Up (Key) then
                        if Scroll > 0 then
                           Scroll := Scroll - 1;
                        end if;
                     elsif Key = Integer (Curses.KEY_NPAGE)
                       or else Key = 4
                       or else Key = 32
                     then
                        if Count > Capacity then
                           Scroll := Natural'Min (Count - Capacity, Scroll + Capacity);
                        end if;
                     elsif Key = Integer (Curses.KEY_PPAGE)
                       or else Key = 21
                     then
                        Scroll := (if Scroll > Capacity then Scroll - Capacity else 0);
                     elsif Key = Character'Pos ('G') then
                        if Count > Capacity then
                           Scroll := Count - Capacity;
                        end if;
                     elsif Key = Character'Pos ('g') then
                        Scroll := 0;
                     elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N') then
                        declare
                           Done : Boolean := False;
                        begin
                           Run_Add (Current_Paths, Done);
                           if Done then
                              Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                           end if;
                        end;
                     elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
                       or else HRA_N.UI.TUI_Input.Is_Redraw (Key)
                     then
                        Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                     end if;
                  end;

               when HRA_N.UI.TUI_Input.Ignored_Input =>
                  null;
            end case;
         end;
      end loop;
   end Run;

end HRA_N.UI.Locus_TUI;
