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
with HRA_N.Application.Assertion_Command; use HRA_N.Application.Assertion_Command;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Line_Edit; use HRA_N.UI.Line_Edit;
with HRA_N.UI.Output; use HRA_N.UI.Output;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with Terminal_Interface.Curses;

package body HRA_N.UI.Balance_TUI is

   package Curses renames Terminal_Interface.Curses;

   Ctrl_L : constant Integer := 12;

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
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : Date_Type;
      Scope        : Balance_Scope;
      Filter_As_Of : Boolean;
      Cursor       : Positive;
      Count        : out Natural)
   is
      View : constant Balance_View :=
        HRA_N.Application.Balance_Query.Execute
          (Paths,
           (Scope      => Scope,
            Has_As_Of  => Filter_As_Of,
            As_Of_Date => Selected_Day));
      Capacity : constant Natural := (if Rows > 8 then Rows - 8 else 0);
      First    : Positive := 1;
      Last     : Natural := 0;
      Scope_Label : constant String :=
        (case Scope is
           when Scope_All          => "ALL",
           when Scope_Known_Only   => "KNOWN ZERO",
           when Scope_Unknown_Only => "UNKNOWN ORIGIN");
   begin
      Curses.Erase;
      Put_Clipped
        (0,
         "HRA-N BALANCES  " & Scope_Label &
         (if Filter_As_Of then " (as-of " & Format_Iso_Date (Selected_Day) & ")" else ""));
      Put_Clipped (1, "============================================================");

      Count := Natural (View.Row_Count);
      if View.Status = Query_Rejected then
         Put_Clipped (3, "AUTHORITY REJECTED");
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
               Put_Clipped
                 (5 + Index - First,
                  (if Index = Cursor then "> " else "  ") &
                  Row_Text (View.Rows (Index)));
            end loop;
         end if;
      end if;

      if Rows > 2 then
         Put_Clipped
           (Rows - 2,
            "j/k: select   a: assert balance   f: scope   t: toggle as-of   b/Esc/q: home");
      end if;
      Curses.Refresh;
   end Draw;

   procedure Run
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : HRA_N.Core.Validity.Date_Type;
      Initial_Scope : HRA_N.Application.Balance_Query.Balance_Scope :=
        HRA_N.Application.Balance_Query.Scope_All)
   is
      Current_Paths : Path_Config := Paths;
      Scope         : Balance_Scope := Initial_Scope;
      Filter_As_Of  : Boolean := False;
      Cursor        : Positive := 1;
      Count         : Natural := 0;
      Running       : Boolean := True;
   begin
      while Running loop
         Draw (Current_Paths, Selected_Day, Scope, Filter_As_Of, Cursor, Count);
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
            elsif (Key = Character'Pos ('a') or else Key = Character'Pos ('A')) and then Count > 0 then
               declare
                  Cur_View : constant Balance_View :=
                    HRA_N.Application.Balance_Query.Execute
                      (Current_Paths,
                       (Scope      => Scope,
                        Has_As_Of  => Filter_As_Of,
                        As_Of_Date => Selected_Day));
               begin
                  if Cur_View.Status /= Query_Rejected and then Cursor <= Natural (Cur_View.Row_Count) then
                     declare
                        Row        : constant Balance_Row := Cur_View.Rows (Cursor);
                        Loc_Str    : constant String := Row.Locus.Value (1 .. Row.Locus.Length);
                        Mea_Str    : constant String := Row.Measure.Value (1 .. Row.Measure.Length);
                        Prompt_Row : constant Natural := (if Rows > 2 then Rows - 1 else 0);
                        Amt_Text   : constant String :=
                          Prompt_For
                            (Prompt_Row,
                             "Assert balance for " & Loc_Str & " (" & Mea_Str & "): ");
                     begin
                        if Amt_Text'Length > 0 then
                           declare
                              Amount_Val : Long_Long_Integer;
                           begin
                              Amount_Val := Long_Long_Integer'Value (Amt_Text);
                              declare
                                 Intent : constant Assertion_Intent :=
                                   (Id          => (Length => 0, Value => [others => ' ']),
                                    Valid_On    =>
                                      (if Filter_As_Of then Selected_Day else Get_System_Date),
                                    Locus       => (Token => Make_Token (Loc_Str)),
                                    Measure     => (Token => Make_Token (Mea_Str)),
                                    Amount      => Quanta_Type (Amount_Val),
                                    Description => Make_Token ("TUI balance assertion"));
                                 Prop_Res : constant Proposal_Result := Propose (Current_Paths, Intent);
                              begin
                                 if not Prop_Res.Success then
                                    Wait_Key
                                      (Prompt_Row,
                                       "Assertion rejected: " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
                                 else
                                    declare
                                       Rec : constant Assertion_Receipt := Commit (Prop_Res.Proposal);
                                    begin
                                       if Rec.Success then
                                          Current_Paths :=
                                            HRA_N.Application.Path_Resolver.Resolve_Paths
                                              (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
                                       else
                                          Wait_Key
                                            (Prompt_Row,
                                             "Commit rejected: " & Rec.Error (1 .. Rec.Error_Len));
                                       end if;
                                    end;
                                 end if;
                              end;
                           exception
                              when others =>
                                 Wait_Key (Prompt_Row, "Invalid integer amount.");
                           end;
                        end if;
                     end;
                  end if;
               end;
            elsif Key = Character'Pos ('f') or else Key = Character'Pos ('F') then
               Scope :=
                 (case Scope is
                    when Scope_All          => Scope_Known_Only,
                    when Scope_Known_Only   => Scope_Unknown_Only,
                    when Scope_Unknown_Only => Scope_All);
               Cursor := 1;
            elsif Key = Character'Pos ('t') or else Key = Character'Pos ('T') then
               Filter_As_Of := not Filter_As_Of;
               Cursor := 1;
            elsif Key = Character'Pos ('r') or else Key = Character'Pos ('R')
              or else Key = Ctrl_L or else Key = Integer (Curses.Key_Resize)
            then
               Current_Paths :=
                 HRA_N.Application.Path_Resolver.Resolve_Paths
                   (HRA_N.Application.Path_Resolver.Data_Dir_Str (Current_Paths));
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Balance_TUI;
