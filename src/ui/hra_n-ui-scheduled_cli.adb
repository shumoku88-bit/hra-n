------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Scheduled_Cli
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings.Fixed;                     use Ada.Strings.Fixed;
with HRA_N.Core.Types;                      use HRA_N.Core.Types;
with HRA_N.Core.Validity;                   use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled;                  use HRA_N.Core.Scheduled;
with HRA_N.Core.Event;                      use HRA_N.Core.Event;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Storage.Scheduled_Journal_Writer; use HRA_N.Storage.Scheduled_Journal_Writer;
with HRA_N.Storage.Journal_Reader;          use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer;          use HRA_N.Storage.Journal_Writer;
with HRA_N.UI.Output;                       use HRA_N.UI.Output;
with HRA_N.UI.Prompt;                       use HRA_N.UI.Prompt;

package body HRA_N.UI.Scheduled_Cli is

   procedure Extract_Flow
     (Occ      : Scheduled_Occurrence;
      From_Str : out String;
      From_Len : out Natural;
      To_Str   : out String;
      To_Len   : out Natural;
      Amount   : out Quanta_Type)
   is
   begin
      From_Len := 0;
      To_Len   := 0;
      Amount   := 0;
      for I in 1 .. Occ.Changes.Count loop
         declare
            Chg     : constant Scheduled_Change := Occ.Changes.Values (I);
            Tok_Str : constant String :=
              Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
         begin
            if Chg.Amount < 0 then
               From_Len := Tok_Str'Length;
               From_Str (From_Str'First .. From_Str'First + From_Len - 1) := Tok_Str;
               Amount := -Chg.Amount;
            elsif Chg.Amount > 0 then
               To_Len := Tok_Str'Length;
               To_Str (To_Str'First .. To_Str'First + To_Len - 1) := Tok_Str;
            end if;
         end;
      end loop;
   end Extract_Flow;

   function Occ_Less (Left, Right : Scheduled_Occurrence) return Boolean is
   begin
      if Left.Expected_Day.Year /= Right.Expected_Day.Year then
         return Left.Expected_Day.Year < Right.Expected_Day.Year;
      elsif Left.Expected_Day.Month /= Right.Expected_Day.Month then
         return Left.Expected_Day.Month < Right.Expected_Day.Month;
      elsif Left.Expected_Day.Day /= Right.Expected_Day.Day then
         return Left.Expected_Day.Day < Right.Expected_Day.Day;
      else
         return Left.Id.Token.Value (1 .. Left.Id.Token.Length) <
                Right.Id.Token.Value (1 .. Right.Id.Token.Length);
      end if;
   end Occ_Less;

   procedure Display_Open_Scheduled (Scheduled_Path : String) is
      Read_Res   : constant Scheduled_Journal_Result :=
        Read_Scheduled_Journal_File (Scheduled_Path);
      Open_Items : Occurrence_Array;
      Open_Count : Scheduled_Count_Type := 0;
   begin
      if not Read_Res.Success then
         Put_Error_Line ("hra-n: failed to read scheduled journal at " & Scheduled_Path);
         Put_Error_Line ("       " & Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
         return;
      end if;

      for I in 1 .. Read_Res.Lifecycle.Sched_Count loop
         declare
            Occ : constant Scheduled_Occurrence := Read_Res.Lifecycle.Sched_Items (I);
         begin
            if Is_Current_Open (Read_Res.Lifecycle, Occ.Id) then
               Open_Count := Open_Count + 1;
               Open_Items (Open_Count) := Occ;
            end if;
         end;
      end loop;

      --  Sort open items by due date ascending
      for I in 2 .. Open_Count loop
         declare
            Key : constant Scheduled_Occurrence := Open_Items (I);
            J   : Natural := I - 1;
         begin
            while J > 0 and then Occ_Less (Key, Open_Items (J)) loop
               Open_Items (J + 1) := Open_Items (J);
               J := J - 1;
            end loop;
            Open_Items (J + 1) := Key;
         end;
      end loop;

      Put_Line ("============================================================");
      Put_Line (" HRA-N: Open Scheduled Obligations (" &
                Trim (Open_Count'Image, Ada.Strings.Both) & " pending)");
      Put_Line ("============================================================");

      if Open_Count = 0 then
         Put_Line ("  No open scheduled obligations found.");
         Put_Line ("============================================================");
         return;
      end if;

      Put_Line ("  DUE DATE    SCHEDULED ID     MOVEMENT FLOW                 AMOUNT");
      Put_Line (" ------------------------------------------------------------");

      for I in 1 .. Open_Count loop
         declare
            Occ      : constant Scheduled_Occurrence := Open_Items (I);
            Id_Str   : constant String := Occ.Id.Token.Value (1 .. Occ.Id.Token.Length);
            Date_Str : constant String := Format_Iso_Date (Occ.Expected_Day);
            From_Buf : String (1 .. Max_Token_Length) := [others => ' '];
            From_Len : Natural := 0;
            To_Buf   : String (1 .. Max_Token_Length) := [others => ' '];
            To_Len   : Natural := 0;
            Amount   : Quanta_Type := 0;
            Meas_Str : constant String :=
              Occ.Measure.Token.Value (1 .. Occ.Measure.Token.Length);
         begin
            Extract_Flow (Occ, From_Buf, From_Len, To_Buf, To_Len, Amount);

            declare
               Id_Col   : constant String := Pad_Right ("[" & Id_Str & "]", 17);
               Flow_Col : constant String :=
                 Pad_Right (From_Buf (1 .. From_Len) & " -> " & To_Buf (1 .. To_Len), 30);
               Amt_Col  : constant String :=
                 Pad_Left (Format_Amount (Amount) & " " & Meas_Str, 12);
            begin
               Put_Line ("  " & Date_Str & "  " & Id_Col & Flow_Col & Amt_Col);
            end;
         end;
      end loop;

      Put_Line ("============================================================");
   end Display_Open_Scheduled;

   procedure Complete_Scheduled
     (Journal_Path    : String;
      Scheduled_Path  : String;
      Target_Str      : String := "";
      Date_Str        : String := "";
      Description_Str : String := "")
   is
      Read_Res : constant Scheduled_Journal_Result :=
        Read_Scheduled_Journal_File (Scheduled_Path);
      Selected_Id_Str : String (1 .. Max_Token_Length) := [others => ' '];
      Selected_Id_Len : Natural := 0;
      Target_Date     : Date_Type;
      Target_Desc     : String (1 .. 128) := [others => ' '];
      Desc_Len        : Natural := 0;
   begin
      if not Read_Res.Success then
         Put_Error_Line ("hra-n: failed to read scheduled journal at " & Scheduled_Path);
         return;
      end if;

      if Target_Str'Length > 0 then
         Selected_Id_Len := Natural'Min (Target_Str'Length, Selected_Id_Str'Length);
         Selected_Id_Str (1 .. Selected_Id_Len) := Target_Str;
      else
         Display_Open_Scheduled (Scheduled_Path);
         declare
            Input : constant String :=
              Prompt_Line ("Select scheduled ID to complete (e.g. scheduled-3) or 'q' to abort: ");
         begin
            if Input'Length = 0 or else Input = "q" or else Input = "Q" then
               Put_Line ("[ABORTED] Scheduled completion cancelled.");
               return;
            end if;
            Selected_Id_Len := Natural'Min (Input'Length, Selected_Id_Str'Length);
            Selected_Id_Str (1 .. Selected_Id_Len) := Input;
         end;
      end if;

      declare
         Sched_Id : constant Scheduled_Id :=
           (Token => Make_Token (Selected_Id_Str (1 .. Selected_Id_Len)));
         Lookup   : constant Lookup_Result :=
           Find_Occurrence (Read_Res.Lifecycle, Sched_Id);
      begin
         if not Lookup.Found then
            Put_Error_Line ("hra-n: scheduled occurrence not found: " &
                            Selected_Id_Str (1 .. Selected_Id_Len));
            return;
         end if;

         if not Is_Current_Open (Read_Res.Lifecycle, Sched_Id) then
            Put_Error_Line ("hra-n: scheduled occurrence is already completed or retired: " &
                            Selected_Id_Str (1 .. Selected_Id_Len));
            return;
         end if;

         if Date_Str'Length > 0 then
            if not Parse_Iso_Date (Date_Str, Target_Date) then
               Put_Error_Line ("hra-n: invalid execution date format: " & Date_Str);
               return;
            end if;
         elsif Target_Str'Length > 0 then
            Target_Date := Lookup.Item.Expected_Day;
         else
            Target_Date := Prompt_Date
              ("Execution date [" & Format_Iso_Date (Lookup.Item.Expected_Day) & "]: ",
               Default => Lookup.Item.Expected_Day);
         end if;

         if Description_Str'Length > 0 then
            Desc_Len := Natural'Min (Description_Str'Length, Target_Desc'Length);
            Target_Desc (1 .. Desc_Len) := Description_Str;
         else
            declare
               Def_Str : constant String :=
                 "Scheduled completion: " & Selected_Id_Str (1 .. Selected_Id_Len);
            begin
               Desc_Len := Def_Str'Length;
               Target_Desc (1 .. Desc_Len) := Def_Str;
            end;
         end if;

         --  Extract flows and append transaction to journal
         declare
            From_Buf : String (1 .. Max_Token_Length) := [others => ' '];
            From_Len : Natural := 0;
            To_Buf   : String (1 .. Max_Token_Length) := [others => ' '];
            To_Len   : Natural := 0;
            Amount   : Quanta_Type := 0;
            Effs     : Effect_List;
            JR       : constant Journal_Result := Read_Journal_File (Journal_Path);
            Ev_Id_Str: constant String := "e" & Trim (Positive'Image (Positive (JR.Events.Length) + 1), Ada.Strings.Both);
            Ev_Id    : constant Event_Id := (Token => Make_Token (Ev_Id_Str));
         begin
            Extract_Flow (Lookup.Item, From_Buf, From_Len, To_Buf, To_Len, Amount);

            Effs.Count := 2;
            Effs.Values (1) :=
              (Key     => (Token => Make_Token ("0")),
               Locus   => (Token => Make_Token (From_Buf (1 .. From_Len))),
               Measure => Lookup.Item.Measure,
               Amount  => (Quanta => -Amount));
            Effs.Values (2) :=
              (Key     => (Token => Make_Token ("1")),
               Locus   => (Token => Make_Token (To_Buf (1 .. To_Len))),
               Measure => Lookup.Item.Measure,
               Amount  => (Quanta => Amount));

            declare
               App_Res : constant Append_Result := Append_Transaction
                 (Journal_Path => Journal_Path,
                  Tx_Id        => Ev_Id_Str,
                  Valid_On     => Target_Date,
                  Effects      => Effs,
                  Description  => Target_Desc (1 .. Desc_Len));
            begin
               if not App_Res.Success then
                  Put_Error_Line ("hra-n: failed to record journal transaction: " &
                                  App_Res.Error_Reason (1 .. App_Res.Error_Len));
                  return;
               end if;
            end;

            --  Update scheduled lifecycle
            declare
               LC     : Scheduled_Lifecycle := Read_Res.Lifecycle;
               WR_Res : Write_Result;
            begin
               LC.Comp_Count := LC.Comp_Count + 1;
               LC.Comp_Items (LC.Comp_Count) := (Scheduled => Sched_Id, Actual => Ev_Id);

               WR_Res := Write_Scheduled_Journal_File (Scheduled_Path, LC);
               if not WR_Res.Success then
                  Put_Error_Line ("hra-n: failed updating scheduled journal: " &
                                  WR_Res.Error_Reason (1 .. WR_Res.Error_Len));
                  return;
               end if;

               Put_Line ("============================================================");
               Put_Line (" [OK] Completed scheduled obligation: " &
                         Selected_Id_Str (1 .. Selected_Id_Len));
               Put_Line ("      Recorded journal receipt: " & Ev_Id_Str);
               Put_Line ("      FLOW : " & From_Buf (1 .. From_Len) & " -> " &
                         To_Buf (1 .. To_Len) & " (" & Format_Amount (Amount) & " jpy)");
               Put_Line ("      DATE : " & Format_Iso_Date (Target_Date));
               Put_Line ("============================================================");
            end;
         end;
      end;
   end Complete_Scheduled;

   procedure Retire_Scheduled
     (Scheduled_Path : String;
      Target_Str     : String := "")
   is
      Read_Res : constant Scheduled_Journal_Result :=
        Read_Scheduled_Journal_File (Scheduled_Path);
      Selected_Id_Str : String (1 .. Max_Token_Length) := [others => ' '];
      Selected_Id_Len : Natural := 0;
   begin
      if not Read_Res.Success then
         Put_Error_Line ("hra-n: failed reading scheduled journal");
         return;
      end if;

      if Target_Str'Length > 0 then
         Selected_Id_Len := Natural'Min (Target_Str'Length, Selected_Id_Str'Length);
         Selected_Id_Str (1 .. Selected_Id_Len) := Target_Str;
      else
         Display_Open_Scheduled (Scheduled_Path);
         declare
            Input : constant String :=
              Prompt_Line ("Select scheduled ID to retire (e.g. scheduled-3) or 'q' to abort: ");
         begin
            if Input'Length = 0 or else Input = "q" or else Input = "Q" then
               Put_Line ("[ABORTED] Scheduled retirement cancelled.");
               return;
            end if;
            Selected_Id_Len := Natural'Min (Input'Length, Selected_Id_Str'Length);
            Selected_Id_Str (1 .. Selected_Id_Len) := Input;
         end;
      end if;

      declare
         Sched_Id : constant Scheduled_Id :=
           (Token => Make_Token (Selected_Id_Str (1 .. Selected_Id_Len)));
         Lookup   : constant Lookup_Result :=
           Find_Occurrence (Read_Res.Lifecycle, Sched_Id);
         LC       : Scheduled_Lifecycle := Read_Res.Lifecycle;
         WR_Res   : Write_Result;
      begin
         if not Lookup.Found then
            Put_Error_Line ("hra-n: scheduled occurrence not found: " &
                            Selected_Id_Str (1 .. Selected_Id_Len));
            return;
         end if;

         if not Is_Current_Open (Read_Res.Lifecycle, Sched_Id) then
            Put_Error_Line ("hra-n: scheduled occurrence is not open");
            return;
         end if;

         LC.Ret_Count := LC.Ret_Count + 1;
         LC.Ret_Items (LC.Ret_Count) := (Scheduled => Sched_Id);

         WR_Res := Write_Scheduled_Journal_File (Scheduled_Path, LC);
         if not WR_Res.Success then
            Put_Error_Line ("hra-n: failed writing scheduled journal: " &
                            WR_Res.Error_Reason (1 .. WR_Res.Error_Len));
            return;
         end if;

         Put_Line (" [OK] Retired scheduled obligation: " & Selected_Id_Str (1 .. Selected_Id_Len));
      end;
   end Retire_Scheduled;

   procedure Add_Scheduled
     (Scheduled_Path : String;
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy")
   is
      pragma Unreferenced (Measure_Str);
      Read_Res : constant Scheduled_Journal_Result :=
        Read_Scheduled_Journal_File (Scheduled_Path);
      LC       : Scheduled_Lifecycle;
      Amount   : Quanta_Type;
      D_Val    : Date_Type;
      WR_Res   : Write_Result;
   begin
      if not Read_Res.Success then
         Put_Error_Line ("hra-n: failed reading scheduled journal");
         return;
      end if;

      if From_Locus'Length = 0 or else To_Locus'Length = 0 or else Amount_Str'Length = 0 then
         Put_Error_Line ("Usage: hra-n scheduled add <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
         return;
      end if;

      begin
         Amount := Quanta_Type'Value (Amount_Str);
      exception
         when others =>
            Put_Error_Line ("hra-n: invalid amount: " & Amount_Str);
            return;
      end;

      if Date_Str'Length > 0 then
         if not Parse_Iso_Date (Date_Str, D_Val) then
            Put_Error_Line ("hra-n: invalid date format: " & Date_Str);
            return;
         end if;
      else
         D_Val := (Year => 2026, Month => 1, Day => 1);
      end if;

      LC := Read_Res.Lifecycle;
      declare
         Next_Num : constant Positive := LC.Sched_Count + 1;
         Next_Id  : constant String := "scheduled-" & Trim (Positive'Image (Next_Num), Ada.Strings.Both);
         Occ      : Scheduled_Occurrence;
      begin
         Occ.Id := (Token => Make_Token (Next_Id));
         Occ.Expected_Day := D_Val;
         Occ.Measure := (Token => Make_Token ("jpy"));
         Occ.Changes.Count := 2;
         Occ.Changes.Values (1) :=
           (Locus => (Token => Make_Token (From_Locus)), Amount => -Amount);
         Occ.Changes.Values (2) :=
           (Locus => (Token => Make_Token (To_Locus)), Amount => Amount);

         LC.Sched_Count := LC.Sched_Count + 1;
         LC.Sched_Items (LC.Sched_Count) := Occ;

         WR_Res := Write_Scheduled_Journal_File (Scheduled_Path, LC);
         if not WR_Res.Success then
            Put_Error_Line ("hra-n: failed writing scheduled journal: " &
                            WR_Res.Error_Reason (1 .. WR_Res.Error_Len));
            return;
         end if;

         Put_Line (" [OK] Added scheduled obligation: " & Next_Id);
      end;
   end Add_Scheduled;

   procedure Replace_Scheduled
     (Scheduled_Path : String;
      Target_Str     : String := "";
      From_Locus     : String := "";
      To_Locus       : String := "";
      Amount_Str     : String := "";
      Date_Str       : String := "";
      Measure_Str    : String := "jpy")
   is
      pragma Unreferenced (Measure_Str);
      Read_Res : constant Scheduled_Journal_Result :=
        Read_Scheduled_Journal_File (Scheduled_Path);
      LC       : Scheduled_Lifecycle;
      Amount   : Quanta_Type;
      D_Val    : Date_Type;
      WR_Res   : Write_Result;
   begin
      if not Read_Res.Success then
         Put_Error_Line ("hra-n: failed reading scheduled journal");
         return;
      end if;

      if Target_Str'Length = 0 or else From_Locus'Length = 0 or else To_Locus'Length = 0 or else Amount_Str'Length = 0 then
         Put_Error_Line ("Usage: hra-n scheduled replace <TARGET_ID> <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
         return;
      end if;

      declare
         Target_Id : constant Scheduled_Id := (Token => Make_Token (Target_Str));
         Lookup    : constant Lookup_Result := Find_Occurrence (Read_Res.Lifecycle, Target_Id);
      begin
         if not Lookup.Found or else not Is_Current_Open (Read_Res.Lifecycle, Target_Id) then
            Put_Error_Line ("hra-n: target scheduled obligation not found or not open: " & Target_Str);
            return;
         end if;

         begin
            Amount := Quanta_Type'Value (Amount_Str);
         exception
            when others =>
               Put_Error_Line ("hra-n: invalid amount: " & Amount_Str);
               return;
         end;

         if Date_Str'Length > 0 then
            if not Parse_Iso_Date (Date_Str, D_Val) then
               Put_Error_Line ("hra-n: invalid date format: " & Date_Str);
               return;
            end if;
         else
            D_Val := Lookup.Item.Expected_Day;
         end if;

         LC := Read_Res.Lifecycle;
         declare
            Next_Num : constant Positive := LC.Sched_Count + 1;
            Next_Id  : constant String := "scheduled-" & Trim (Positive'Image (Next_Num), Ada.Strings.Both);
            Occ      : Scheduled_Occurrence;
         begin
            Occ.Id := (Token => Make_Token (Next_Id));
            Occ.Expected_Day := D_Val;
            Occ.Measure := (Token => Make_Token ("jpy"));
            Occ.Changes.Count := 2;
            Occ.Changes.Values (1) :=
              (Locus => (Token => Make_Token (From_Locus)), Amount => -Amount);
            Occ.Changes.Values (2) :=
              (Locus => (Token => Make_Token (To_Locus)), Amount => Amount);

            LC.Sched_Count := LC.Sched_Count + 1;
            LC.Sched_Items (LC.Sched_Count) := Occ;

            LC.Repl_Count := LC.Repl_Count + 1;
            LC.Repl_Items (LC.Repl_Count) :=
              (Original => Target_Id, Replaced_By => (Token => Make_Token (Next_Id)));

            WR_Res := Write_Scheduled_Journal_File (Scheduled_Path, LC);
            if not WR_Res.Success then
               Put_Error_Line ("hra-n: failed writing scheduled journal: " &
                               WR_Res.Error_Reason (1 .. WR_Res.Error_Len));
               return;
            end if;

            Put_Line (" [OK] Replaced scheduled obligation " & Target_Str & " with " & Next_Id);
         end;
      end;
   end Replace_Scheduled;

   procedure Dispatch
     (Paths       : Path_Config;
      Command     : String;
      Command_Idx : Positive;
      Rem_Args    : Natural)
   is
      Sched_Path : constant String := Scheduled_Path_Str (Paths);
      Journ_Path : constant String := Journal_Path_Str (Paths);
   begin
      if Command = "scheduled" or else Command = "open-scheduled" then
         if Rem_Args = 0 then
            Display_Open_Scheduled (Sched_Path);
            return;
         end if;

         declare
            Subcmd : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
         begin
            if Subcmd = "add" then
               if Rem_Args < 4 then
                  Put_Line ("Usage: hra-n scheduled add <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
                  return;
               end if;
               Add_Scheduled
                 (Scheduled_Path => Sched_Path,
                  From_Locus     => Ada.Command_Line.Argument (Command_Idx + 2),
                  To_Locus       => Ada.Command_Line.Argument (Command_Idx + 3),
                  Amount_Str     => Ada.Command_Line.Argument (Command_Idx + 4),
                  Date_Str       => (if Rem_Args >= 4 then Ada.Command_Line.Argument (Command_Idx + 5) else ""));
            elsif Subcmd = "retire" then
               Retire_Scheduled
                 (Scheduled_Path => Sched_Path,
                  Target_Str     => (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else ""));
            elsif Subcmd = "replace" then
               if Rem_Args < 5 then
                  Put_Line ("Usage: hra-n scheduled replace <TARGET_ID> <FROM> <TO> <AMOUNT> [YYYY-MM-DD]");
                  return;
               end if;
               Replace_Scheduled
                 (Scheduled_Path => Sched_Path,
                  Target_Str     => Ada.Command_Line.Argument (Command_Idx + 2),
                  From_Locus     => Ada.Command_Line.Argument (Command_Idx + 3),
                  To_Locus       => Ada.Command_Line.Argument (Command_Idx + 4),
                  Amount_Str     => Ada.Command_Line.Argument (Command_Idx + 5),
                  Date_Str       => (if Rem_Args >= 5 then Ada.Command_Line.Argument (Command_Idx + 6) else ""));
            else
               Display_Open_Scheduled (Sched_Path);
            end if;
         end;
      elsif Command = "complete" then
         Complete_Scheduled
           (Journal_Path    => Journ_Path,
            Scheduled_Path  => Sched_Path,
            Target_Str      => (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else ""),
            Date_Str        => (if Rem_Args >= 2 then Ada.Command_Line.Argument (Command_Idx + 2) else ""),
            Description_Str => (if Rem_Args >= 3 then Ada.Command_Line.Argument (Command_Idx + 3) else ""));
      elsif Command = "retire" then
         Retire_Scheduled
           (Scheduled_Path => Sched_Path,
            Target_Str     => (if Rem_Args >= 1 then Ada.Command_Line.Argument (Command_Idx + 1) else ""));
      end if;
   end Dispatch;

end HRA_N.UI.Scheduled_Cli;
