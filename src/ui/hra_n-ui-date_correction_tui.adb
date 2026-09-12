with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Proposal;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_Style;
with HRA_N.UI.Terminal_UTF8; use HRA_N.UI.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA_N.UI.Date_Correction_TUI is

   package Curses renames Terminal_Interface.Curses;

   type Editor_Mode is (Mode_Editing, Mode_Preview);

   function Token_String (Token : Token_Text) return String is
     (Token.Value (1 .. Token.Length));

   function Amount_Image (Amount : Quanta_Type) return String is
     (Trim (Amount'Image, Ada.Strings.Both));

   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Detail       : HRA_N.Application.Actual_Detail_Query.Actual_Detail_View;
      New_Event_Id : out HRA_N.Core.Types.Token_Text;
      Committed    : out Boolean)
   is
      Current_Paths : constant HRA_N.Application.Path_Resolver.Path_Config := Paths;
      Running       : Boolean := True;
      Mode          : Editor_Mode := Mode_Editing;

      Original_Date_Str : constant String :=
        (if Detail.Has_Date then Format_Iso_Date (Detail.Valid_On) else "2026-01-01");
      Date_Buf     : String (1 .. 10) := [others => ' '];
      Date_Len     : Natural := 0;
      Notice       : String (1 .. 128) := [others => ' '];
      Notice_Len   : Natural := 0;

      New_Date     : Date_Type;
      Proposal_Obj : HRA_N.Application.Movement_Command.Movement_Proposal;

      From_Locus   : Token_Text := (0, [others => ' ']);
      To_Locus     : Token_Text := (0, [others => ' ']);
      Measure_Tok  : Token_Text := (0, [others => ' ']);
      Amount_Val   : Quanta_Type := 0;

      procedure Set_Notice (Msg : String) is
      begin
         Notice_Len := Natural'Min (Msg'Length, Notice'Length);
         Notice (1 .. Notice_Len) := Msg (Msg'First .. Msg'First + Notice_Len - 1);
      end Set_Notice;

      procedure Draw_Editing is
         R : Natural := 0;
      begin
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped (R, "================================================================================");
         R := R + 1;
         Put_Clipped (R, " CORRECT ACTUAL DATE: " & Token_String (Detail.Event_Id));
         R := R + 1;
         Put_Clipped (R, "================================================================================");
         R := R + 1;

         R := R + 1;
         Put_Clipped (R, " Target Event : " & Token_String (Detail.Event_Id));
         R := R + 1;
         Put_Clipped (R, " Current Date : " & Original_Date_Str);
         R := R + 1;

         if Detail.Description.Length > 0 then
            Put_Clipped (R, " Description  : " & To_String (Detail.Description));
            R := R + 1;
         end if;

         Put_Clipped (R, " Amount       : " & Amount_Image (Amount_Val) & " " & Token_String (Measure_Tok));
         R := R + 1;
         Put_Clipped (R, " Movement     : " & Token_String (From_Locus) & " -> " & Token_String (To_Locus));
         R := R + 2;

         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Selected_Style);
         Put_Clipped (R, "> New Date (YYYY-MM-DD): [" & Date_Buf (1 .. Date_Len) & "_]");
         HRA_N.UI.Terminal_Style.Reset;
         R := R + 2;

         if Notice_Len > 0 then
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped (R, " Notice: " & Notice (1 .. Notice_Len));
            HRA_N.UI.Terminal_Style.Reset;
         end if;

         if Rows > 2 then
            Put_Clipped (Rows - 2, "[Enter] preview   [Backspace] erase   [Esc / q] cancel");
         end if;
         Curses.Refresh;
      end Draw_Editing;

      procedure Draw_Preview is
         R : Natural := 0;
      begin
         Curses.Erase;
         HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Header_Style);
         Put_Clipped (R, "================================================================================");
         R := R + 1;
         Put_Clipped (R, " DATE CORRECTION - ADMISSION PREVIEW");
         R := R + 1;
         Put_Clipped (R, "================================================================================");
         R := R + 1;

         R := R + 1;
         Put_Clipped (R, " Proposed ID  : " & HRA_N.Application.Proposal.Primary_Id (Proposal_Obj));
         R := R + 1;
         Put_Clipped (R, " Replaces     : " & Token_String (Detail.Event_Id) & " (will be superseded)");
         R := R + 1;
         Put_Clipped (R, " Original Date: " & Original_Date_Str);
         R := R + 1;
         Put_Clipped (R, " Corrected To : " & Format_Iso_Date (New_Date));
         R := R + 1;

         if Detail.Description.Length > 0 then
            Put_Clipped (R, " Description  : " & To_String (Detail.Description));
            R := R + 1;
         end if;

         Put_Clipped (R, " Flow         : " & Token_String (From_Locus) & " -> " & Token_String (To_Locus) & " (" & Amount_Image (Amount_Val) & " " & Token_String (Measure_Tok) & ")");
         R := R + 2;

         Put_Clipped (R, "--------------------------------------------------------------------------------");
         R := R + 1;
         Put_Clipped (R, " Ready to commit date correction to authority.");

         if Notice_Len > 0 then
            R := R + 2;
            HRA_N.UI.Terminal_Style.Apply (HRA_N.UI.Terminal_Style.Error_Style);
            Put_Clipped (R, " Notice: " & Notice (1 .. Notice_Len));
            HRA_N.UI.Terminal_Style.Reset;
         end if;

         if Rows > 2 then
            Put_Clipped (Rows - 2, "[Enter] commit to authority   [e / Esc] edit date   [q] cancel");
         end if;
         Curses.Refresh;
      end Draw_Preview;

   begin
      Committed := False;
      New_Event_Id := (0, [others => ' ']);

      if Detail.Effect_Count /= 2 then
         return;
      end if;

      for Index in 1 .. Detail.Effect_Count loop
         if Detail.Effects (Index).Amount < 0 then
            From_Locus := Detail.Effects (Index).Locus;
            Measure_Tok := Detail.Effects (Index).Measure;
            if Amount_Val = 0 then
               Amount_Val := abs Detail.Effects (Index).Amount;
            end if;
         elsif Detail.Effects (Index).Amount > 0 then
            To_Locus := Detail.Effects (Index).Locus;
            Measure_Tok := Detail.Effects (Index).Measure;
            if Amount_Val = 0 then
               Amount_Val := Detail.Effects (Index).Amount;
            end if;
         end if;
      end loop;

      Date_Len := Original_Date_Str'Length;
      Date_Buf (1 .. Date_Len) := Original_Date_Str;

      while Running loop
         if Mode = Mode_Editing then
            Draw_Editing;
         else
            Draw_Preview;
         end if;

         declare
            Event : constant Input_Event := Read_Input;
            Is_Char : constant Boolean :=
              Event.Kind = Character_Input;
            Key : constant Integer :=
              (case Event.Kind is
                  when Character_Input =>
                     Integer (Event.Code_Point),
                  when Special_Key_Input =>
                     Event.Key_Code);
         begin
            if Mode = Mode_Editing then
               if Is_Char and then Key = 27 then
                  Running := False;
               elsif Is_Char and then (Key = Character'Pos ('q') or else Key = Character'Pos ('Q')) then
                  Running := False;
               elsif (Is_Char and then Key in 8 | 127)
                 or else (not Is_Char and then Key = Integer (Curses.KEY_BACKSPACE))
               then
                  if Date_Len > 0 then
                     Date_Buf (Date_Len) := ' ';
                     Date_Len := Date_Len - 1;
                     Notice_Len := 0;
                  end if;
               elsif Is_Char and then Key in 10 | 13 then
                  if Date_Len = 0 then
                     Set_Notice ("Date cannot be blank.");
                  elsif not Parse_Iso_Date (Date_Buf (1 .. Date_Len), New_Date) then
                     Set_Notice ("Date must be a real YYYY-MM-DD calendar date.");
                  else
                     declare
                        Intent : constant Correction_Intent :=
                          (Target_Id   => Detail.Event_Id,
                           From_Locus  => (Token => From_Locus),
                           To_Locus    => (Token => To_Locus),
                           Measure     => (Token => Measure_Tok),
                           Amount      => Amount_Val,
                           Valid_On    => New_Date,
                           Description =>
                             (if Detail.Description.Length > 0
                              then Make_Token (To_String (Detail.Description))
                              else (0, [others => ' '])));
                        Prop_Res : constant Proposal_Result :=
                          Propose_Correction (Current_Paths, Intent);
                     begin
                        if Prop_Res.Success then
                           Proposal_Obj := Prop_Res.Proposal;
                           Mode := Mode_Preview;
                           Notice_Len := 0;
                        else
                           Set_Notice (Prop_Res.Error (1 .. Prop_Res.Error_Len));
                        end if;
                     end;
                  end if;
               elsif Is_Char and then Key in Character'Pos ('0') .. Character'Pos ('9') | Character'Pos ('-') then
                  if Date_Len < 10 then
                     Date_Len := Date_Len + 1;
                     Date_Buf (Date_Len) := Character'Val (Key);
                     Notice_Len := 0;
                  end if;
               end if;
            else
               --  Mode_Preview
               if (Is_Char and then Key in 10 | 13)
                 or else (not Is_Char and then (Key = Integer (Curses.KEY_ENTER) or else Key = Integer (Curses.Key_Enter_Or_Send)))
               then
                  declare
                     Receipt : constant Movement_Receipt :=
                       HRA_N.Application.Proposal.Commit (Proposal_Obj);
                  begin
                     if Receipt.Success then
                        Committed := True;
                        New_Event_Id :=
                          Make_Token (Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                        Running := False;
                     else
                        Set_Notice ("Commit rejected: " & Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               elsif Is_Char and then (Key = Character'Pos ('e') or else Key = Character'Pos ('E') or else Key = 27) then
                  Mode := Mode_Editing;
                  Notice_Len := 0;
               elsif Is_Char and then (Key = Character'Pos ('q') or else Key = Character'Pos ('Q')) then
                  Running := False;
               end if;
            end if;
         end;
      end loop;
   end Run;

end HRA_N.UI.Date_Correction_TUI;
