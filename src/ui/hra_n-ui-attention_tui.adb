-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Attention_TUI
-------------------------------------------------------------------------------

with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Attention_Command; use HRA_N.Application.Attention_Command;
with HRA_N.Application.Attention_Query; use HRA_N.Application.Attention_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Line_Edit; use HRA_N.UI.Line_Edit;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Snapshot_Label;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Attention_TUI is

   package Curses renames Terminal_Interface.Curses;

   Ctrl_L : constant Integer := 12;

   function Token_String (Token : Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Row_Text (Row : Attention_Row) return String is
      Ctx : constant String :=
        Row.Context.Value (1 .. Row.Context.Length);
      Short_Ctx : constant String :=
        (if Ctx'Length > 48 then Ctx (Ctx'First .. Ctx'First + 47) & ".."
         else Ctx);
   begin
      return Pad_Right (Token_String (Row.Id), 10) & "  " &
             Pad_Right (Due_Label (Row.Due), 22) & "  " & Short_Ctx;
   end Row_Text;

   --  Shared raise editor. Empty context cancels; due accepts a date,
   --  `none`, or blank for undetermined.
   procedure Run_Raise (Paths : Path_Config; Committed : out Boolean) is
      Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
      Ctx_Text : constant String :=
        Prompt_For (Prompt_Row, "Matter: ", "", False, Max_Description_Length);
      Due_Text   : constant String :=
        (if Ctx_Text'Length = 0 then ""
         else Prompt_For
           (Prompt_Row, "Due (YYYY-MM-DD, none, blank for unknown): ",
            "", True));
      Due        : Attention_Due;
      Known_Text : constant String := Due_Text;
   begin
      Committed := False;
      if Ctx_Text'Length = 0 then
         return;
      elsif Known_Text = "none" then
         Due := (Kind => No_Due_Date);
      elsif Known_Text'Length = 0 then
         Due := (Kind => Due_Undetermined);
      else
         declare
            Parsed : Date_Type;
         begin
            if not Parse_Iso_Date (Known_Text, Parsed) then
               Wait_Key (Prompt_Row, "Due must be YYYY-MM-DD, none, or blank.");
               return;
            end if;
            Due := (Kind => Due_On_Date, Due_Date => Parsed);
         end;
      end if;

      declare
         Intent : constant Raise_Intent :=
           (Context => Make_Description (Ctx_Text),
            Due     => Due);
         Prop_Res : constant Proposal_Result :=
           Propose_Raise (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Wait_Key
              (Prompt_Row,
               "Raise rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            return;
         end if;
         Curses.Erase;
         Put_Clipped (0, "ATTENTION RAISE PREVIEW  " & Proposed_Item_Id (Prop_Res.Proposal));
         Put_Clipped (1, "============================================================");
         Put_Clipped (3, "Matter     " & Ctx_Text);
         Put_Clipped (4, "Due        " & Due_Label (Due));
         if not Confirm (Prompt_Row, "Raise this matter?") then
            return;
         end if;
         declare
            Receipt : constant Attention_Receipt := Commit (Prop_Res.Proposal);
         begin
            if Receipt.Success then
               Committed := True;
            else
               Wait_Key
                 (Prompt_Row,
                  "Raise commit rejected: "
                  & Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
   end Run_Raise;

   --  Shared close editor for one retained identity and lifecycle kind.
   procedure Run_Close
     (Paths     : Path_Config;
      Target_Id : Token_Text;
      Kind      : Closure_Kind;
      Committed : out Boolean)
   is
      Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
      Kind_Text  : constant String :=
        (if Kind = Closure_Resolved then "resolved" else "dropped");
   begin
      Committed := False;
      if not Confirm
        (Prompt_Row,
         "Mark " & Token_String (Target_Id) & " " & Kind_Text & "?")
      then
         return;
      end if;
      declare
         Intent : constant Close_Intent :=
           (Target_Id => Target_Id,
            Kind      => Kind,
            Known_On  => Get_System_Date);
         Prop_Res : constant Proposal_Result :=
           Propose_Close (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Wait_Key
              (Prompt_Row,
               "Close rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
            return;
         end if;
         declare
            Receipt : constant Attention_Receipt := Commit (Prop_Res.Proposal);
         begin
            if Receipt.Success then
               Committed := True;
            else
               Wait_Key
                 (Prompt_Row,
                  "Close commit rejected: "
                  & Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
   end Run_Close;

   procedure Draw (Paths : Path_Config; Cursor : Positive; Count : out Natural) is
      View : constant Attention_View := Execute (Paths);
      Capacity : constant Natural := (if Rows > 8 then Rows - 8 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
   begin
      Curses.Erase;
      Put_Clipped (0, "HRA-N ATTENTION");
      Put_Clipped (1, "============================================================");

      Count := 0;
      if View.Status = Query_Rejected then
         Put_Clipped (3, "AUTHORITY REJECTED");
         Put_Clipped (4, View.Diagnostic (1 .. View.Diagnostic_Len));
      else
         Count := View.Count;
         if Count = 0 then
            Put_Clipped (3, "No open matters. (An empty stream is not unavailable.)");
         else
            Put_Clipped (3, "  ID          DUE                     MATTER");
            Put_Clipped (4, "  --------------------------------------------------------");
            if Capacity > 0 then
               if Cursor > Capacity then
                  First := Cursor - Capacity + 1;
               end if;
               Last := Natural'Min (Count, First + Capacity - 1);
               for Index in First .. Last loop
                  Put_Clipped
                    (5 + Index - First,
                     (if Index = Cursor then "> " else "  ") &
                     Row_Text (View.Rows (Index)));
               end loop;
            end if;
         end if;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 3,
            "Snapshot: " & HRA_N.UI.Snapshot_Label.Format (View.Snapshot));
         Put_Clipped
           (Rows - 2,
            "j/k: select   n: raise   r: resolve   x: drop   R: reload   b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run (Paths : Path_Config) is
      Current_Paths : Path_Config := Paths;
      Cursor        : Positive := 1;
      Count         : Natural := 0;
      Running       : Boolean := True;
   begin
      while Running loop
         Draw (Current_Paths, Cursor, Count);
         declare
            Key : constant Integer := Integer (Curses.Get_Keystroke);
         begin
            if Key = Character'Pos ('b') or else Key = Character'Pos ('B')
              or else Key = Character'Pos ('q') or else Key = Character'Pos ('Q')
              or else Key = 27
            then
               Running := False;
            elsif Key = Character'Pos ('j') or else Key = Integer (Curses.KEY_DOWN) then
               if Count > 0 and then Cursor < Count then
                  Cursor := Cursor + 1;
               end if;
            elsif Key = Character'Pos ('k') or else Key = Integer (Curses.KEY_UP) then
               if Cursor > 1 then
                  Cursor := Cursor - 1;
               end if;
            elsif Key = Character'Pos ('n') or else Key = Character'Pos ('N') then
               declare
                  Done : Boolean := False;
               begin
                  Run_Raise (Current_Paths, Done);
                  if Done then
                     Current_Paths :=
                       Resolve_Paths (Data_Dir_Str (Current_Paths));
                     Cursor := 1;
                  end if;
               end;
            elsif (Key = Character'Pos ('r') or else Key = Character'Pos ('x'))
              and then Count > 0
            then
               declare
                  View : constant Attention_View := Execute (Current_Paths);
                  Done : Boolean := False;
               begin
                  if View.Success and then Cursor <= View.Count then
                     Run_Close
                       (Current_Paths,
                        View.Rows (Cursor).Id,
                        (if Key = Character'Pos ('r')
                         then Closure_Resolved else Closure_Dropped),
                        Done);
                  end if;
                  if Done then
                     Current_Paths :=
                       Resolve_Paths (Data_Dir_Str (Current_Paths));
                     Cursor := 1;
                  end if;
               end;
            elsif Key = Character'Pos ('R')
              or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
            then
               Current_Paths :=
                 Resolve_Paths (Data_Dir_Str (Current_Paths));
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Attention_TUI;
