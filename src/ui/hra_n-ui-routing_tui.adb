-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Routing_TUI
-------------------------------------------------------------------------------

with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Proposal;
with HRA_N.Application.Policy_Command; use HRA_N.Application.Policy_Command;
with HRA_N.Application.Policy_Query;   use HRA_N.Application.Policy_Query;
with HRA_N.Application.Path_Resolver;  use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Actual_Routing;        use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.UI.Line_Edit;               use HRA_N.UI.Line_Edit;
with HRA_N.UI.Terminal;                use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Routing_TUI is

   package Curses renames Terminal_Interface.Curses;
   Ctrl_L : constant Integer := 12;

   function Token_String (Value : Token_Text) return String is
     (Value.Value (1 .. Value.Length));

   procedure Run_Editor
     (Paths     : Path_Config;
      Selected  : Date_Type;
      Seed      : String;
      Managed   : Boolean;
      Committed : out Boolean)
   is
      Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
      Locus_Text : constant String :=
        Prompt_For (Prompt_Row, "Locus: ", Seed);
      Purpose_Text : constant String :=
        (if Locus_Text'Length = 0 or else not Managed then ""
         else Prompt_For (Prompt_Row, "Purpose: "));
      Effective_Text : constant String :=
        (if Locus_Text'Length = 0
           or else (Managed and then Purpose_Text'Length = 0)
         then ""
         else Prompt_For
           (Prompt_Row,
            "Effective (initial or YYYY-MM-DD, blank for "
            & Format_Iso_Date (Selected) & "): ", "", True));
      Kind : Routing_Effective_Kind := Routing_From_Date;
      Date : Date_Type := Selected;
   begin
      Committed := False;
      if Locus_Text'Length = 0
        or else (Managed and then Purpose_Text'Length = 0)
      then
         return;
      elsif Effective_Text = "initial" then
         Kind := Routing_Initial;
         Date := (Year => 1900, Month => 1, Day => 1);
      elsif Effective_Text'Length > 0
        and then not Parse_Iso_Date (Effective_Text, Date)
      then
         Wait_Key
           (Prompt_Row, "Effective coordinate must be initial or YYYY-MM-DD.");
         return;
      end if;

      if Locus_Text'Length > Max_Token_Length
        or else Purpose_Text'Length > Max_Token_Length
      then
         Wait_Key (Prompt_Row, "Locus or purpose is too long.");
         return;
      end if;

      declare
         Intent : constant Routing_Intent :=
           (Locus          => (Token => Make_Token (Locus_Text)),
            Effective_Kind => Kind,
            Effective_On   => Date,
            Managed        => Managed,
            Purpose        => Make_Token (Purpose_Text));
         Proposed : constant Proposal_Result := Propose_Routing (Paths, Intent);
      begin
         if not Proposed.Success then
            Wait_Key
              (Prompt_Row,
               "Routing rejected: "
               & Proposed.Error (1 .. Proposed.Error_Len));
            return;
         end if;
         Curses.Erase;
         Put_Clipped
           (0, "ACTUAL ROUTING PREVIEW  " & Locus_Text);
         Put_Clipped (1, "============================================================");
         Put_Clipped (3, "Locus      " & Locus_Text);
         Put_Clipped
           (4, "Effective  "
            & (if Kind = Routing_Initial then "initial"
               else Format_Iso_Date (Date)));
         Put_Clipped
           (5, "Target     "
            & (if Managed then Purpose_Text else "UNMANAGED"));
         Put_Clipped
           (6, "Snapshot   "
            & HRA_N.Application.Proposal.Expected_Snapshot
              (Proposed.Proposal));
         if not Confirm (Prompt_Row, "Commit this routing assertion?") then
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
                  "Routing commit rejected: "
                  & Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
   end Run_Editor;

   procedure Draw
     (Paths    : Path_Config;
      Selected : Date_Type;
      History  : Boolean;
      Cursor   : in out Positive;
      Count    : out Natural)
   is
      View : constant Routing_View :=
        Execute_Routing_Query (Paths, Selected, History);
      Capacity : constant Natural := (if Rows > 8 then Rows - 8 else 0);
   begin
      Curses.Erase;
      Put_Clipped
        (0, "ACTUAL ROUTING  "
         & (if History then "RETAINED HISTORY"
            else "AS OF " & Format_Iso_Date (Selected)));
      Put_Clipped (1, "============================================================");
      Count := 0;
      if View.Status = Query_Rejected then
         if View.Diagnostic_Len > 0 then
            Put_Clipped
              (3, "! " & View.Diagnostic (1 .. View.Diagnostic_Len));
         end if;
      else
         Count := View.Row_Count;
         if Count = 0 then
            Cursor := 1;
            Put_Clipped (3, "No routing assertions in this projection.");
         else
            if Cursor > Count then
               Cursor := Positive (Count);
            end if;
            Put_Clipped (3, "  LOCUS              EFFECTIVE    TARGET");
            for I in 1 .. Natural'Min (Count, Capacity) loop
               declare
                  Row : constant Routing_View_Row := View.Rows (I);
                  Prefix : constant String := (if I = Cursor then "> " else "  ");
                  Effective : constant String :=
                    (if Row.Effective_Kind = Routing_Initial then "initial"
                     else Format_Iso_Date (Row.Effective_On));
                  Target : constant String :=
                    (if Row.Managed then Token_String (Row.Purpose)
                     else "UNMANAGED");
               begin
                  Put_Clipped
                    (3 + I, Prefix & Token_String (Row.Locus)
                     & "  " & Effective & "  " & Target);
               end;
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
            "j/k: select  n: managed  u: unmanaged  h: history  R: reload  b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths    : Path_Config;
      Selected : Date_Type)
   is
      Current_Paths : Path_Config := Paths;
      Cursor  : Positive := 1;
      Count   : Natural := 0;
      History : Boolean := False;
      Running : Boolean := True;
   begin
      while Running loop
         Draw (Current_Paths, Selected, History, Cursor, Count);
         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
              or else Key = Character'Pos ('q') or else Key = Character'Pos ('Q')
              or else Key = 27
            then
               Running := False;
            elsif Key = Character'Pos ('j')
              or else Key = Integer (Curses.KEY_DOWN)
            then
               if Count > 0 and then Cursor < Count then
                  Cursor := Cursor + 1;
               end if;
            elsif Key = Character'Pos ('k')
              or else Key = Integer (Curses.KEY_UP)
            then
               if Cursor > 1 then
                  Cursor := Cursor - 1;
               end if;
            elsif Key = Integer (Curses.KEY_NPAGE)
              or else Key = 4
              or else Key = 32
            then
               declare
                  Step : constant Positive :=
                    Positive'Max (1, (if Rows > 9 then Rows - 9 else 5));
               begin
                  Cursor := (if Count > 0 then Natural'Min (Count, Cursor + Step) else 1);
               end;
            elsif Key = Integer (Curses.KEY_PPAGE)
              or else Key = 21
            then
               declare
                  Step : constant Positive :=
                    Positive'Max (1, (if Rows > 9 then Rows - 9 else 5));
               begin
                  Cursor := (if Cursor > Step then Cursor - Step else 1);
               end;
            elsif Key = Character'Pos ('G') then
               if Count > 0 then
                  Cursor := Count;
               end if;
            elsif Key = Character'Pos ('g') then
               Cursor := 1;
            elsif Key = Character'Pos ('h') or else Key = Character'Pos ('H') then
               History := not History;
               Cursor := 1;
            elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N')
              or else Key = Character'Pos ('u') or else Key = Character'Pos ('U')
            then
               declare
                  View : constant Routing_View :=
                    Execute_Routing_Query (Current_Paths, Selected, History);
                  Seed : constant String :=
                    (if View.Status = Query_Complete
                       and then View.Row_Count > 0 and then Cursor <= View.Row_Count
                     then Token_String (View.Rows (Cursor).Locus) else "");
                  Done : Boolean := False;
               begin
                  Run_Editor
                    (Current_Paths, Selected, Seed,
                     Key = Character'Pos ('n') or else Key = Character'Pos ('N'),
                     Done);
                  if Done then
                     Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
                     Cursor := 1;
                  end if;
               end;
            elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
              or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
            then
               Current_Paths := Resolve_Paths (Data_Dir_Str (Current_Paths));
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Routing_TUI;
