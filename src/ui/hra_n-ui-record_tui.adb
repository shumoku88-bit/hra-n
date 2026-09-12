-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Record_TUI
--
--  Unified keyboard-first posting editor integrating:
--    1. HRA double-entry posting workflow: Description first, multi-row postings,
--       Ctrl-N add row, Ctrl-D drop row, signed JPY quantities.
--    2. Loam ergonomics: Smart-Enter progression (Description -> Locus ->
--       Amount -> Next Posting -> Preview), real-time balanced diff feedback,
--       and role context in candidate picker.
-------------------------------------------------------------------------------

with Ada.Characters.Handling;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.UI.Terminal; use HRA_N.UI.Terminal;
with HRA_N.UI.Terminal_UTF8;
with Terminal_Interface.Curses;

package body HRA_N.UI.Record_TUI is

   package Curses renames Terminal_Interface.Curses;
   use type HRA_N.UI.Terminal_UTF8.Input_Kind;

   Ctrl_L : constant Integer := 12;
   Ctrl_N : constant Integer := 14;
   Ctrl_D : constant Integer := 4;

   Max_Postings : constant := 8;
   subtype Posting_Index_Type is Positive range 1 .. Max_Postings;

   type Field_Kind is (Field_Description, Field_Locus, Field_Amount);

   type Focus_Type is record
      Kind          : Field_Kind          := Field_Description;
      Posting_Index : Posting_Index_Type := 1;
   end record;

   type Editor_Mode is (Mode_Editing, Mode_Preview);

   type Posting_Entry is record
      Locus_Str : String (1 .. 32) := [others => ' '];
      Locus_Len : Natural := 0;
      Amt_Str   : String (1 .. 18) := [others => ' '];
      Amt_Len   : Natural := 0;
   end record;

   type Posting_Array is array (Posting_Index_Type) of Posting_Entry;

   Max_Loci : constant := 64;
   type Locus_Entry is record
      Token : Token_Text;
      Role  : Accounting_Role;
   end record;
   type Locus_Array is array (1 .. Max_Loci) of Locus_Entry;
   type Filtered_Array is array (1 .. Max_Loci) of Positive;

   function Role_Name (Role : Accounting_Role) return String is
     (case Role is
        when Role_Asset     => "asset",
        when Role_Liability => "liability",
        when Role_Equity    => "equity",
        when Role_Income    => "income",
        when Role_Expense   => "expense");

   function Pad_Right (Str : String; Width : Natural) return String is
   begin
      if Str'Length >= Width then
         return Str;
      else
         return Str & String'(1 .. Width - Str'Length => ' ');
      end if;
   end Pad_Right;

   function Pad_Left (Str : String; Width : Natural) return String is
   begin
      if Str'Length >= Width then
         return Str;
      else
         return String'(1 .. Width - Str'Length => ' ') & Str;
      end if;
   end Pad_Left;

   function Format_Quanta_With_Commas (Amount : Quanta_Type) return String is
      Is_Neg       : constant Boolean := Amount < 0;
      Abs_Val      : constant Quanta_Type := (if Is_Neg then -Amount else Amount);
      Raw          : constant String := Trim (Quanta_Type'Image (Abs_Val), Ada.Strings.Both);
      Result       : String (1 .. Raw'Length + Raw'Length / 3 + 3);
      Res_Len      : Natural := 0;
      Digits_Count : Natural := 0;
   begin
      for I in reverse Raw'Range loop
         if Raw (I) in '0' .. '9' then
            if Digits_Count > 0 and then Digits_Count mod 3 = 0 then
               Res_Len := Res_Len + 1;
               Result (Result'Last - Res_Len + 1) := ',';
            end if;
            Digits_Count := Digits_Count + 1;
         end if;
         Res_Len := Res_Len + 1;
         Result (Result'Last - Res_Len + 1) := Raw (I);
      end loop;
      if Is_Neg then
         Res_Len := Res_Len + 1;
         Result (Result'Last - Res_Len + 1) := '-';
      end if;
      return Result (Result'Last - Res_Len + 1 .. Result'Last);
   end Format_Quanta_With_Commas;

   function Parse_Signed_Quanta
     (Str : String;
      Val : out Quanta_Type) return Boolean
   is
      Trimmed : constant String := Trim (Str, Both);
   begin
      if Trimmed'Length = 0 then
         return False;
      end if;
      Val := Quanta_Type'Value (Trimmed);
      return Val /= 0;
   exception
      when others =>
         return False;
   end Parse_Signed_Quanta;

   procedure Run_Unified
     (Paths         : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day  : HRA_N.Core.Validity.Date_Type;
      Is_Correction : Boolean;
      Init          : Movement_Initial_Values;
      New_Event_Id  : out Token_Text;
      Committed     : out Boolean)
   is
      Running : Boolean := True;
      Mode    : Editor_Mode := Mode_Editing;
      Focus   : Focus_Type := (Kind => Field_Description, Posting_Index => 1);

      Posting_Count : Posting_Index_Type := 2;
      Postings      : Posting_Array;

      Desc_Str  : String (1 .. 128) := [others => ' '];
      Desc_Len  : Natural := 0;

      Notice     : String (1 .. 160) := [others => ' '];
      Notice_Len : Natural := 0;

      Target_Str : constant String :=
        Init.Target_Id.Value (1 .. Init.Target_Id.Length);

      Proposal : Movement_Proposal;

      Policy     : constant Policy_Result := Read_Policy_File (Policy_Path_Str (Paths));
      Loci       : Locus_Array;
      Loci_Count : Natural := 0;

      Filtered_Loci  : Filtered_Array;
      Filtered_Count : Natural := 0;
      Cand_Idx       : Positive := 1;

      procedure Set_Notice (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Notice'Length);
      begin
         Notice_Len := L;
         Notice (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Set_Notice;

      function Lookup_Locus_Role (Token_Str : String) return String is
      begin
         for I in 1 .. Loci_Count loop
            declare
               Tok : constant String :=
                 Loci (I).Token.Value (1 .. Loci (I).Token.Length);
            begin
               if Tok = Token_Str then
                  return Role_Name (Loci (I).Role);
               end if;
            end;
         end loop;
         return "";
      end Lookup_Locus_Role;

      procedure Update_Candidates (Pattern : String) is
         Lower_Pat : constant String :=
           Ada.Characters.Handling.To_Lower (Pattern);
      begin
         Filtered_Count := 0;
         Cand_Idx := 1;
         if Pattern'Length = 0 then
            for I in 1 .. Loci_Count loop
               Filtered_Count := Filtered_Count + 1;
               Filtered_Loci (Filtered_Count) := I;
            end loop;
            return;
         end if;

         --  1. Prefix matches first
         for I in 1 .. Loci_Count loop
            declare
               Tok       : constant String :=
                 Loci (I).Token.Value (1 .. Loci (I).Token.Length);
               Lower_Tok : constant String :=
                 Ada.Characters.Handling.To_Lower (Tok);
            begin
               if Pattern'Length <= Tok'Length
                 and then Lower_Tok (Lower_Tok'First .. Lower_Tok'First + Pattern'Length - 1) = Lower_Pat
               then
                  Filtered_Count := Filtered_Count + 1;
                  Filtered_Loci (Filtered_Count) := I;
               end if;
            end;
         end loop;

         --  2. Substring matches if not already included
         for I in 1 .. Loci_Count loop
            declare
               Tok       : constant String :=
                 Loci (I).Token.Value (1 .. Loci (I).Token.Length);
               Lower_Tok : constant String :=
                 Ada.Characters.Handling.To_Lower (Tok);
               Already   : Boolean := False;
            begin
               for J in 1 .. Filtered_Count loop
                  if Filtered_Loci (J) = I then
                     Already := True;
                     exit;
                  end if;
               end loop;
               if not Already and then Index (Lower_Tok, Lower_Pat) > 0 then
                  Filtered_Count := Filtered_Count + 1;
                  Filtered_Loci (Filtered_Count) := I;
               end if;
            end;
         end loop;
      end Update_Candidates;

      procedure Next_Field is
      begin
         case Focus.Kind is
            when Field_Description =>
               Focus := (Kind => Field_Locus, Posting_Index => 1);
               Update_Candidates
                 (Postings (1).Locus_Str (1 .. Postings (1).Locus_Len));
            when Field_Locus =>
               Focus := (Kind => Field_Amount, Posting_Index => Focus.Posting_Index);
            when Field_Amount =>
               if Focus.Posting_Index < Posting_Count then
                  Focus := (Kind => Field_Locus, Posting_Index => Focus.Posting_Index + 1);
                  Update_Candidates
                    (Postings (Focus.Posting_Index).Locus_Str (1 .. Postings (Focus.Posting_Index).Locus_Len));
               else
                  Focus := (Kind => Field_Description, Posting_Index => 1);
               end if;
         end case;
      end Next_Field;

      procedure Prev_Field is
      begin
         case Focus.Kind is
            when Field_Description =>
               Focus := (Kind => Field_Amount, Posting_Index => Posting_Count);
            when Field_Locus =>
               if Focus.Posting_Index = 1 then
                  Focus := (Kind => Field_Description, Posting_Index => 1);
               else
                  Focus := (Kind => Field_Amount, Posting_Index => Focus.Posting_Index - 1);
               end if;
            when Field_Amount =>
               Focus := (Kind => Field_Locus, Posting_Index => Focus.Posting_Index);
               Update_Candidates
                 (Postings (Focus.Posting_Index).Locus_Str (1 .. Postings (Focus.Posting_Index).Locus_Len));
         end case;
      end Prev_Field;

      procedure Add_Posting_Row is
      begin
         if Posting_Count < Max_Postings then
            Posting_Count := Posting_Count + 1;
            Postings (Posting_Count) :=
              (Locus_Str => [others => ' '],
               Locus_Len => 0,
               Amt_Str   => [others => ' '],
               Amt_Len   => 0);
            Focus := (Kind => Field_Locus, Posting_Index => Posting_Count);
            Update_Candidates ("");
            Notice_Len := 0;
         else
            Set_Notice ("Maximum of " & Trim (Max_Postings'Image, Both) & " postings reached.");
         end if;
      end Add_Posting_Row;

      procedure Drop_Posting_Row is
      begin
         if Posting_Count > 2 then
            Posting_Count := Posting_Count - 1;
            if Focus.Posting_Index > Posting_Count then
               Focus := (Kind => Field_Amount, Posting_Index => Posting_Count);
            end if;
            Notice_Len := 0;
         else
            Set_Notice ("Transaction requires at least two postings.");
         end if;
      end Drop_Posting_Row;

      procedure Accept_Candidate_And_Advance is
      begin
         if Focus.Kind = Field_Locus then
            if Filtered_Count > 0 and then Cand_Idx <= Filtered_Count then
               declare
                  Chosen_Locus : constant Locus_Entry :=
                    Loci (Filtered_Loci (Cand_Idx));
                  Tok : constant String :=
                    Chosen_Locus.Token.Value (1 .. Chosen_Locus.Token.Length);
               begin
                  Postings (Focus.Posting_Index).Locus_Len := Tok'Length;
                  Postings (Focus.Posting_Index).Locus_Str (1 .. Tok'Length) := Tok;
               end;
            end if;
            Focus := (Kind => Field_Amount, Posting_Index => Focus.Posting_Index);
         end if;
      end Accept_Candidate_And_Advance;

      procedure Append_Character
        (Code_Point : HRA_N.UI.Terminal_UTF8.Unicode_Code_Point)
      is
      begin
         Notice_Len := 0;
         case Focus.Kind is
            when Field_Description =>
               if Code_Point >= 32 and then Code_Point /= Character'Pos ('"') then
                  declare
                     Encoded : constant String :=
                       HRA_N.UI.Terminal_UTF8.Append_Code_Point ("", Code_Point);
                  begin
                     if Encoded'Length <= Desc_Str'Length - Desc_Len then
                        Desc_Str (Desc_Len + 1 .. Desc_Len + Encoded'Length) := Encoded;
                        Desc_Len := Desc_Len + Encoded'Length;
                     end if;
                  end;
               end if;

            when Field_Locus =>
               if Code_Point in 32 .. 126
                 and then Postings (Focus.Posting_Index).Locus_Len < 32
               then
                  declare
                     Idx : constant Posting_Index_Type := Focus.Posting_Index;
                  begin
                     Postings (Idx).Locus_Len := Postings (Idx).Locus_Len + 1;
                     Postings (Idx).Locus_Str (Postings (Idx).Locus_Len) :=
                       Character'Val (Code_Point);
                     Update_Candidates
                       (Postings (Idx).Locus_Str (1 .. Postings (Idx).Locus_Len));
                  end;
               end if;

            when Field_Amount =>
               declare
                  Idx : constant Posting_Index_Type := Focus.Posting_Index;
               begin
                  if (Code_Point in Character'Pos ('0') .. Character'Pos ('9'))
                    or else (Code_Point in Character'Pos ('-') | Character'Pos ('+')
                             and then Postings (Idx).Amt_Len = 0)
                  then
                     if Postings (Idx).Amt_Len < 18 then
                        Postings (Idx).Amt_Len := Postings (Idx).Amt_Len + 1;
                        Postings (Idx).Amt_Str (Postings (Idx).Amt_Len) :=
                          Character'Val (Code_Point);
                     end if;
                  end if;
               end;
         end case;
      end Append_Character;

      procedure Delete_Char is
      begin
         Notice_Len := 0;
         case Focus.Kind is
            when Field_Description =>
               if Desc_Len > 0 then
                  declare
                     Dropped : constant String :=
                       HRA_N.UI.Terminal_UTF8.Drop_Last_Code_Point
                         (Desc_Str (1 .. Desc_Len));
                  begin
                     Desc_Len := Dropped'Length;
                     if Desc_Len > 0 then
                        Desc_Str (1 .. Desc_Len) := Dropped;
                     end if;
                  end;
               end if;

            when Field_Locus =>
               declare
                  Idx : constant Posting_Index_Type := Focus.Posting_Index;
               begin
                  Postings (Idx).Locus_Len :=
                    Natural'Max (0, Postings (Idx).Locus_Len - 1);
                  Update_Candidates
                    (Postings (Idx).Locus_Str (1 .. Postings (Idx).Locus_Len));
               end;

            when Field_Amount =>
               declare
                  Idx : constant Posting_Index_Type := Focus.Posting_Index;
               begin
                  Postings (Idx).Amt_Len :=
                    Natural'Max (0, Postings (Idx).Amt_Len - 1);
               end;
         end case;
      end Delete_Char;

      procedure Compute_Balance
        (All_Filled : out Boolean;
         All_Valid  : out Boolean;
         Sum        : out Long_Long_Integer;
         Pos_Total  : out Quanta_Type)
      is
      begin
         All_Filled := True;
         All_Valid  := True;
         Sum        := 0;
         Pos_Total  := 0;

         for I in 1 .. Posting_Count loop
            if Postings (I).Locus_Len = 0 or else Postings (I).Amt_Len = 0 then
               All_Filled := False;
            else
               declare
                  Val : Quanta_Type;
               begin
                  if Parse_Signed_Quanta
                       (Postings (I).Amt_Str (1 .. Postings (I).Amt_Len), Val)
                  then
                     Sum := Sum + Long_Long_Integer (Val);
                     if Val > 0 then
                        Pos_Total := Pos_Total + Val;
                     end if;
                  else
                     All_Valid := False;
                  end if;
               end;
            end if;
         end loop;
      end Compute_Balance;

      procedure Try_Propose is
         All_Filled : Boolean;
         All_Valid  : Boolean;
         Sum        : Long_Long_Integer;
         Pos_Total  : Quanta_Type;
         Res        : Proposal_Result;
      begin
         Notice_Len := 0;

         Compute_Balance (All_Filled, All_Valid, Sum, Pos_Total);

         if not All_Filled then
            Set_Notice ("Every posting requires both a Locus and an Amount.");
            return;
         end if;

         if not All_Valid then
            Set_Notice ("Invalid amount found. Must be a non-zero signed integer.");
            return;
         end if;

         if Sum /= 0 then
            declare
               Diff_Str : constant String :=
                 (if Sum > 0
                  then "+" & Format_Quanta_With_Commas (Quanta_Type (Sum))
                  else Format_Quanta_With_Commas (Quanta_Type (Sum)));
            begin
               Set_Notice
                 ("Postings must balance to zero. Unbalanced diff: " &
                  Diff_Str & " jpy");
            end;
            return;
         end if;

         --  Check locus uniqueness
         for I in 1 .. Posting_Count loop
            for J in I + 1 .. Posting_Count loop
               if Postings (I).Locus_Str (1 .. Postings (I).Locus_Len) =
                  Postings (J).Locus_Str (1 .. Postings (J).Locus_Len)
               then
                  Set_Notice ("Duplicate locus: " &
                              Postings (I).Locus_Str (1 .. Postings (I).Locus_Len));
                  return;
               end if;
            end loop;
         end loop;

         --  Admit proposals
         if Is_Correction then
            --  Correction: if exactly 2 postings with 1 negative and 1 positive, use Propose_Correction
            if Posting_Count = 2 then
               declare
                  Val1, Val2 : Quanta_Type;
                  P1_Ok : constant Boolean :=
                    Parse_Signed_Quanta (Postings (1).Amt_Str (1 .. Postings (1).Amt_Len), Val1);
                  P2_Ok : constant Boolean :=
                    Parse_Signed_Quanta (Postings (2).Amt_Str (1 .. Postings (2).Amt_Len), Val2);
               begin
                  pragma Assert (P1_Ok and P2_Ok);
                  declare
                     From_Loc : constant String :=
                       (if Val1 < 0
                        then Postings (1).Locus_Str (1 .. Postings (1).Locus_Len)
                        else Postings (2).Locus_Str (1 .. Postings (2).Locus_Len));
                     To_Loc   : constant String :=
                       (if Val1 > 0
                        then Postings (1).Locus_Str (1 .. Postings (1).Locus_Len)
                        else Postings (2).Locus_Str (1 .. Postings (2).Locus_Len));
                     Amt      : constant Quanta_Type := (if Val1 > 0 then Val1 else Val2);
                     Intent   : constant Correction_Intent :=
                       (Target_Id   => Init.Target_Id,
                        From_Locus  => (Token => Make_Token (From_Loc)),
                        To_Locus    => (Token => Make_Token (To_Loc)),
                        Measure     => (Token => Make_Token ("jpy")),
                        Amount      => Amt,
                        Valid_On    => Selected_Day,
                        Description => Make_Token (Desc_Str (1 .. Desc_Len)));
                  begin
                     Res := Propose_Correction (Paths, Intent);
                  end;
               end;
            else
               Set_Notice ("Correction currently supports 2-leg replacement.");
               return;
            end if;
         else
            --  Standard recording:
            --  If 2 postings (1 negative and 1 positive), use Propose for automatic routing/purpose
            if Posting_Count = 2 then
               declare
                  Val1, Val2 : Quanta_Type;
                  P1_Ok : constant Boolean :=
                    Parse_Signed_Quanta (Postings (1).Amt_Str (1 .. Postings (1).Amt_Len), Val1);
                  P2_Ok : constant Boolean :=
                    Parse_Signed_Quanta (Postings (2).Amt_Str (1 .. Postings (2).Amt_Len), Val2);
               begin
                  pragma Assert (P1_Ok and P2_Ok);
                  if (Val1 < 0 and Val2 > 0) or else (Val1 > 0 and Val2 < 0) then
                     declare
                        From_Loc : constant String :=
                          (if Val1 < 0
                           then Postings (1).Locus_Str (1 .. Postings (1).Locus_Len)
                           else Postings (2).Locus_Str (1 .. Postings (2).Locus_Len));
                        To_Loc   : constant String :=
                          (if Val1 > 0
                           then Postings (1).Locus_Str (1 .. Postings (1).Locus_Len)
                           else Postings (2).Locus_Str (1 .. Postings (2).Locus_Len));
                        Amt      : constant Quanta_Type := (if Val1 > 0 then Val1 else Val2);
                        Intent   : constant Movement_Intent :=
                          (From_Locus  => (Token => Make_Token (From_Loc)),
                           To_Locus    => (Token => Make_Token (To_Loc)),
                           Measure     => (Token => Make_Token ("jpy")),
                           Amount      => Amt,
                           Valid_On    => Selected_Day,
                           Description => Make_Token (Desc_Str (1 .. Desc_Len)));
                     begin
                        Res := Propose (Paths, Intent);
                     end;
                  else
                     --  Both negative or both positive (which shouldn't happen if sum=0)
                     Set_Notice ("2-posting movement must have one outflow and one inflow.");
                     return;
                  end if;
               end;
            else
               --  Multi-leg movement (3..8 postings): use Propose_Split
               declare
                  Intent : Record_Split_Intent;
               begin
                  Intent.Count := Natural (Posting_Count);
                  Intent.Valid_On := Selected_Day;
                  Intent.Description := Make_Token (Desc_Str (1 .. Desc_Len));
                  for I in 1 .. Posting_Count loop
                     declare
                        Val : Quanta_Type;
                        V_Ok : constant Boolean :=
                          Parse_Signed_Quanta (Postings (I).Amt_Str (1 .. Postings (I).Amt_Len), Val);
                     begin
                        pragma Assert (V_Ok);
                        Intent.Changes (I) :=
                          (Locus   => (Token => Make_Token (Postings (I).Locus_Str (1 .. Postings (I).Locus_Len))),
                           Measure => (Token => Make_Token ("jpy")),
                           Amount  => Val);
                     end;
                  end loop;
                  Res := Propose_Split (Paths, Intent);
               end;
            end if;
         end if;

         if Res.Success then
            Proposal := Res.Proposal;
            Mode := Mode_Preview;
         else
            Set_Notice (Res.Error (1 .. Res.Error_Len));
         end if;
      end Try_Propose;

      procedure Handle_Enter is
      begin
         Notice_Len := 0;
         case Focus.Kind is
            when Field_Description =>
               Focus := (Kind => Field_Locus, Posting_Index => 1);
               Update_Candidates
                 (Postings (1).Locus_Str (1 .. Postings (1).Locus_Len));

            when Field_Locus =>
               Accept_Candidate_And_Advance;

            when Field_Amount =>
               if Focus.Posting_Index < Posting_Count then
                  --  Loam ergonomic progression: advance to next posting Locus
                  Focus := (Kind => Field_Locus, Posting_Index => Focus.Posting_Index + 1);
                  Update_Candidates
                    (Postings (Focus.Posting_Index).Locus_Str (1 .. Postings (Focus.Posting_Index).Locus_Len));
               else
                  --  Last posting amount: propose and proceed to preview
                  Try_Propose;
               end if;
         end case;
      end Handle_Enter;

      procedure Draw_Editing is
         Max_R        : constant Natural := Rows;
         Max_C        : constant Natural := Columns;
         Cursor_Row   : Natural := 0;
         Cursor_Col   : Natural := 0;
         Cursor_Found : Boolean := False;
         Current_Row  : Natural := 0;

         All_Filled   : Boolean;
         All_Valid    : Boolean;
         Sum          : Long_Long_Integer;
         Pos_Total    : Quanta_Type;
      begin
         Curses.Erase;

         --  Header
         declare
            Title : constant String :=
              (if Is_Correction
               then "Correct Actual: " & Target_Str & " (" & Format_Iso_Date (Selected_Day) & ")  "
               else "Record Actual: " & Format_Iso_Date (Selected_Day) & "  ");
            Snap_Str : constant String :=
              (if Paths.Is_Versioned then Snapshot_Id_Str (Paths) else "(unversioned)");
         begin
            Put_Clipped (Current_Row, "================================================================================");
            Current_Row := Current_Row + 1;
            Put_Clipped (Current_Row, " " & Title & Snap_Str);
            Current_Row := Current_Row + 1;
            Put_Clipped (Current_Row, "================================================================================");
            Current_Row := Current_Row + 1;
         end;

         Put_Clipped
           (Current_Row,
            " Signed postings must balance. Outflow is negative (-), Inflow is positive (+).");
         Current_Row := Current_Row + 1;

         --  Description field
         declare
            Is_Focused : constant Boolean := (Focus.Kind = Field_Description);
            Prefix     : constant String := (if Is_Focused then "> Description : [" else "  Description : [");
            Suffix     : constant String := (if Is_Focused then "_" else " ") & "]";
         begin
            Put_Clipped (Current_Row, Prefix & Desc_Str (1 .. Desc_Len) & Suffix);
            if Is_Focused then
               Cursor_Row   := Current_Row;
               Cursor_Col   := Prefix'Length + HRA_N.UI.Terminal_UTF8.Display_Width (Desc_Str (1 .. Desc_Len));
               Cursor_Found := True;
            end if;
            Current_Row := Current_Row + 1;
         end;

         --  Posting fields
         for I in 1 .. Posting_Count loop
            if Current_Row < Max_R - 9 then
               declare
                  Idx_Str : constant String := Trim (I'Image, Both);
               begin
                  Put_Clipped (Current_Row, "  Posting " & Idx_Str & ":");
                  Current_Row := Current_Row + 1;

                  --  Locus line
                  declare
                     Is_Focused : constant Boolean :=
                       (Focus.Kind = Field_Locus and then Focus.Posting_Index = I);
                     Prefix     : constant String :=
                       (if Is_Focused then "  > Locus   : [" else "    Locus   : [");
                     Suffix     : constant String := (if Is_Focused then "_" else " ") & "]";
                     Role_Str   : constant String :=
                       Lookup_Locus_Role (Postings (I).Locus_Str (1 .. Postings (I).Locus_Len));
                     Role_Hint  : constant String :=
                       (if Role_Str'Length > 0 then "  (" & Role_Str & ")" else "");
                  begin
                     Put_Clipped
                       (Current_Row,
                        Prefix & Postings (I).Locus_Str (1 .. Postings (I).Locus_Len) & Suffix & Role_Hint);
                     if Is_Focused then
                        Cursor_Row   := Current_Row;
                        Cursor_Col   := Prefix'Length + Postings (I).Locus_Len;
                        Cursor_Found := True;
                     end if;
                     Current_Row := Current_Row + 1;
                  end;

                  --  Amount line
                  declare
                     Is_Focused : constant Boolean :=
                       (Focus.Kind = Field_Amount and then Focus.Posting_Index = I);
                     Prefix     : constant String :=
                       (if Is_Focused then "  > Amount  : [" else "    Amount  : [");
                     Suffix     : constant String := (if Is_Focused then "_" else " ") & "] jpy";
                  begin
                     Put_Clipped
                       (Current_Row,
                        Prefix & Postings (I).Amt_Str (1 .. Postings (I).Amt_Len) & Suffix);
                     if Is_Focused then
                        Cursor_Row   := Current_Row;
                        Cursor_Col   := Prefix'Length + Postings (I).Amt_Len;
                        Cursor_Found := True;
                     end if;
                     Current_Row := Current_Row + 1;
                  end;
               end;
            end if;
         end loop;

         --  Candidate listing (Loam / HRA picker)
         if Focus.Kind = Field_Locus and then Current_Row < Max_R - 6 then
            Put_Clipped
              (Current_Row,
               "  Candidate loci [Up/Down: pick, Enter/Right: accept]:");
            Current_Row := Current_Row + 1;

            if Filtered_Count > 0 then
               declare
                  Max_Visible : constant Positive := 4;
                  Start_Idx   : constant Positive :=
                    (if Cand_Idx > Max_Visible then Cand_Idx - Max_Visible + 1 else 1);
                  End_Idx     : constant Positive :=
                    Positive'Min (Filtered_Count, Start_Idx + Max_Visible - 1);
               begin
                  for I in Start_Idx .. End_Idx loop
                     if Current_Row < Max_R - 4 then
                        declare
                           L_Idx    : constant Positive := Filtered_Loci (I);
                           Tok      : constant String :=
                             Loci (L_Idx).Token.Value (1 .. Loci (L_Idx).Token.Length);
                           Role_Str : constant String := Role_Name (Loci (L_Idx).Role);
                           Prefix   : constant String := (if I = Cand_Idx then "   > " else "     ");
                        begin
                           Put_Clipped
                             (Current_Row,
                              Prefix & Pad_Right (Tok, 16) & " (" & Role_Str & ")");
                           Current_Row := Current_Row + 1;
                        end;
                     end if;
                  end loop;
                  if Filtered_Count > End_Idx and then Current_Row < Max_R - 4 then
                     Put_Clipped
                       (Current_Row,
                        "     ... (" & Trim (Natural'Image (Filtered_Count - End_Idx), Both) & " more)");
                     Current_Row := Current_Row + 1;
                  end if;
               end;
            else
               Put_Clipped (Current_Row, "     (no matching loci in Policy)");
               Current_Row := Current_Row + 1;
            end if;
         end if;

         --  Real-time Balance status bar (Loam UI ergonomics)
         Compute_Balance (All_Filled, All_Valid, Sum, Pos_Total);
         if Max_R > 5 then
            declare
               Bal_Row : constant Natural := Max_R - 4;
            begin
               if not All_Filled then
                  Put_Clipped (Bal_Row, " Balance: Waiting for postings...");
               elsif not All_Valid then
                  Put_Clipped (Bal_Row, " Balance: Invalid non-integer amount entered.");
               elsif Sum = 0 and then Pos_Total > 0 then
                  Put_Clipped
                    (Bal_Row,
                     " Balance: Balanced (Total: " & Format_Quanta_With_Commas (Pos_Total) & " jpy)");
               else
                  declare
                     Diff_Str : constant String :=
                       (if Sum > 0
                        then "+" & Format_Quanta_With_Commas (Quanta_Type (Sum))
                        else Format_Quanta_With_Commas (Quanta_Type (Sum)));
                  begin
                     Put_Clipped
                       (Bal_Row,
                        " Balance: Unbalanced (Diff: " & Diff_Str & " jpy)");
                  end;
               end if;
            end;
         end if;

         --  Notice
         if Notice_Len > 0 and then Max_R > 3 then
            Put_Clipped (Max_R - 3, " ! " & Notice (1 .. Notice_Len));
         end if;

         --  Footer keyboard shortcuts
         if Max_R > 2 then
            if Focus.Kind = Field_Locus then
               Put_Clipped
                 (Max_R - 2,
                  "[Tab/Shift-Tab] nav  [Up/Down] pick  [Enter] accept & next  [Ctrl-N] add row  [Esc] cancel");
            else
               Put_Clipped
                 (Max_R - 2,
                  "[Tab/Shift-Tab] nav  [Enter] next / preview  [Ctrl-N] add row  [Ctrl-D] drop row  [Esc] cancel");
            end if;
         end if;

         --  Move cursor
         if Cursor_Found and then Cursor_Row < Max_R and then Cursor_Col < Max_C then
            Curses.Move_Cursor
              (Line   => Curses.Line_Position (Cursor_Row),
               Column => Curses.Column_Position (Cursor_Col));
         end if;

         Curses.Refresh;
      end Draw_Editing;

      procedure Draw_Preview is
         Max_R       : constant Natural := Rows;
         Current_Row : Natural := 0;

         All_Filled  : Boolean;
         All_Valid   : Boolean;
         Sum         : Long_Long_Integer;
         Pos_Total   : Quanta_Type;
      begin
         Curses.Erase;

         Put_Clipped (Current_Row, "================================================================================");
         Current_Row := Current_Row + 1;
         Put_Clipped
           (Current_Row,
            (if Is_Correction
             then " CORRECT ACTUAL - ADMISSION PREVIEW"
             else " RECORD ACTUAL - ADMISSION PREVIEW"));
         Current_Row := Current_Row + 1;
         Put_Clipped (Current_Row, "================================================================================");
         Current_Row := Current_Row + 1;

         Put_Clipped (Current_Row, " Proposed ID:  " & Proposed_Event_Id (Proposal));
         Current_Row := Current_Row + 1;

         if Is_Correction then
            Put_Clipped (Current_Row, " Replaces:     " & Replaced_Target_Id (Proposal) & " (will be superseded)");
            Current_Row := Current_Row + 1;
         end if;

         Put_Clipped (Current_Row, " Date:         " & Format_Iso_Date (Selected_Day));
         Current_Row := Current_Row + 1;

         if Desc_Len > 0 then
            Put_Clipped (Current_Row, " Description:  " & Desc_Str (1 .. Desc_Len));
         else
            Put_Clipped (Current_Row, " Description:  (none)");
         end if;
         Current_Row := Current_Row + 1;

         Put_Clipped (Current_Row, "");
         Current_Row := Current_Row + 1;

         Put_Clipped (Current_Row, " Postings:");
         Current_Row := Current_Row + 1;

         Compute_Balance (All_Filled, All_Valid, Sum, Pos_Total);

         for I in 1 .. Posting_Count loop
            if Current_Row < Max_R - 6 then
               declare
                  Val : Quanta_Type := 0;
                  V_Ok : constant Boolean :=
                    Parse_Signed_Quanta (Postings (I).Amt_Str (1 .. Postings (I).Amt_Len), Val);
                  pragma Unreferenced (V_Ok);
                  Amt_Formatted : constant String :=
                    (if Val > 0
                     then "+" & Format_Quanta_With_Commas (Val)
                     else Format_Quanta_With_Commas (Val));
                  Role_Str : constant String :=
                    Lookup_Locus_Role (Postings (I).Locus_Str (1 .. Postings (I).Locus_Len));
               begin
                  Put_Clipped
                    (Current_Row,
                     "   " & Trim (I'Image, Both) & ". " &
                     Pad_Right (Postings (I).Locus_Str (1 .. Postings (I).Locus_Len), 18) & "  " &
                     Pad_Left (Amt_Formatted, 12) & " jpy  (" & Role_Str & ")");
                  Current_Row := Current_Row + 1;
               end;
            end if;
         end loop;

         Put_Clipped (Current_Row, "");
         Current_Row := Current_Row + 1;

         Put_Clipped
           (Current_Row,
            " Total:        " & Format_Quanta_With_Commas (Pos_Total) & " jpy (balanced)");
         Current_Row := Current_Row + 1;

         Put_Clipped
           (Current_Row,
            " Snapshot:     " & Expected_Snapshot (Proposal) & " -> next immutable generation");
         Current_Row := Current_Row + 1;

         Put_Clipped (Current_Row, "--------------------------------------------------------------------------------");
         Current_Row := Current_Row + 1;
         Put_Clipped (Current_Row, " Ready to commit to authority.");

         if Notice_Len > 0 and then Max_R > 3 then
            Put_Clipped (Max_R - 3, " ! " & Notice (1 .. Notice_Len));
         end if;

         if Max_R > 2 then
            Put_Clipped
              (Max_R - 2,
               "[Enter] commit to authority   [e / Esc] edit draft   [q] cancel");
         end if;

         if Max_R > 0 and then Columns > 0 then
            Curses.Move_Cursor (Line => 0, Column => 0);
         end if;

         Curses.Refresh;
      end Draw_Preview;

   begin
      Committed := False;
      New_Event_Id := (Length => 0, Value => [others => ' ']);

      --  Load candidate loci from Policy
      if Policy.Success then
         for I in 1 .. Natural (Entry_Count (Policy.Roles)) loop
            if Loci_Count < Max_Loci then
               declare
                  Assign : constant Role_Assignment := Entry_At (Policy.Roles, I);
               begin
                  Loci_Count := Loci_Count + 1;
                  Loci (Loci_Count) :=
                    (Token => Assign.Locus.Token,
                     Role  => Assign.Role);
               end;
            end if;
         end loop;
      end if;

      --  Initialize values
      if Is_Correction then
         if Init.Description.Length > 0 then
            Desc_Len := Init.Description.Length;
            Desc_Str (1 .. Desc_Len) := Init.Description.Value (1 .. Desc_Len);
         end if;
         if Init.From_Locus.Length > 0 and then Init.Amount > 0 then
            Postings (1).Locus_Len := Init.From_Locus.Length;
            Postings (1).Locus_Str (1 .. Postings (1).Locus_Len) :=
              Init.From_Locus.Value (1 .. Init.From_Locus.Length);
            declare
               Amt_Text : constant String :=
                 Trim (Quanta_Type'Image (-Init.Amount), Both);
            begin
               Postings (1).Amt_Len := Amt_Text'Length;
               Postings (1).Amt_Str (1 .. Amt_Text'Length) := Amt_Text;
            end;
         end if;
         if Init.To_Locus.Length > 0 and then Init.Amount > 0 then
            Postings (2).Locus_Len := Init.To_Locus.Length;
            Postings (2).Locus_Str (1 .. Postings (2).Locus_Len) :=
              Init.To_Locus.Value (1 .. Init.To_Locus.Length);
            declare
               Amt_Text : constant String :=
                 Trim (Quanta_Type'Image (Init.Amount), Both);
            begin
               Postings (2).Amt_Len := Amt_Text'Length;
               Postings (2).Amt_Str (1 .. Amt_Text'Length) := Amt_Text;
            end;
         end if;
      end if;

      Update_Candidates ("");

      while Running loop
         if Mode = Mode_Editing then
            Draw_Editing;
         else
            Draw_Preview;
         end if;

         declare
            Event : constant HRA_N.UI.Terminal_UTF8.Input_Event :=
              HRA_N.UI.Terminal_UTF8.Read_Input;
            Is_Character : constant Boolean :=
              Event.Kind = HRA_N.UI.Terminal_UTF8.Character_Input;
            Key : constant Integer :=
              (case Event.Kind is
                  when HRA_N.UI.Terminal_UTF8.Character_Input =>
                     Integer (Event.Code_Point),
                  when HRA_N.UI.Terminal_UTF8.Special_Key_Input =>
                     Event.Key_Code);
         begin
            if Mode = Mode_Editing then
               if Is_Character and then Key = 27 then
                  --  Cancel: discard draft
                  Running := False;
               elsif Is_Character and then Key = 9 then
                  --  Tab: advance field
                  Next_Field;
               elsif not Is_Character
                 and then (Key = Integer (Curses.KEY_BTAB)
                           or else Key = Integer (Curses.Key_Back_Tab))
               then
                  --  BackTab / Shift-Tab
                  Prev_Field;
               elsif Is_Character and then Key = Ctrl_N then
                  Add_Posting_Row;
               elsif Is_Character and then Key = Ctrl_D then
                  Drop_Posting_Row;
               elsif not Is_Character and then Key = Integer (Curses.KEY_DOWN) then
                  if Focus.Kind = Field_Locus and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx < Filtered_Count then Cand_Idx + 1 else 1);
                  else
                     Next_Field;
                  end if;
               elsif not Is_Character and then Key = Integer (Curses.KEY_UP) then
                  if Focus.Kind = Field_Locus and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx > 1 then Cand_Idx - 1 else Filtered_Count);
                  else
                     Prev_Field;
                  end if;
               elsif not Is_Character
                 and then (Key = Integer (Curses.KEY_RIGHT)
                           or else Key = Integer (Curses.Key_Cursor_Right))
               then
                  if Focus.Kind = Field_Locus then
                     Accept_Candidate_And_Advance;
                  else
                     Next_Field;
                  end if;
               elsif not Is_Character
                 and then (Key = Integer (Curses.KEY_LEFT)
                           or else Key = Integer (Curses.Key_Cursor_Left))
               then
                  if Focus.Kind = Field_Locus and then Filtered_Count > 1 then
                     Cand_Idx := (if Cand_Idx > 1 then Cand_Idx - 1 else Filtered_Count);
                  else
                     Prev_Field;
                  end if;
               elsif (Is_Character and then Key in 8 | 127)
                 or else (not Is_Character
                          and then (Key = Integer (Curses.KEY_BACKSPACE)
                                    or else Key = Integer (Curses.Key_Backspace)))
               then
                  Delete_Char;
               elsif (Is_Character and then Key in 10 | 13)
                 or else (not Is_Character
                          and then (Key = Integer (Curses.KEY_ENTER)
                                    or else Key = Integer (Curses.Key_Enter_Or_Send)))
               then
                  Handle_Enter;
               elsif Is_Character and then Key >= 32 then
                  Append_Character (Event.Code_Point);
               elsif (Is_Character and then Key = Ctrl_L)
                 or else (not Is_Character
                          and then Key = Integer (Curses.Key_Resize))
               then
                  null;
               end if;
            else
               --  Mode_Preview
               if (Is_Character and then Key in 10 | 13)
                 or else (not Is_Character
                          and then (Key = Integer (Curses.KEY_ENTER)
                                    or else Key = Integer (Curses.Key_Enter_Or_Send)))
               then
                  declare
                     Receipt : constant Movement_Receipt := Commit (Proposal);
                  begin
                     if Receipt.Success then
                        Committed := True;
                        New_Event_Id :=
                          Make_Token (Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                        Running := False;
                     else
                        Set_Notice
                          ("Commit rejected: " &
                           Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               elsif Is_Character
                 and then (Key = Character'Pos ('e')
                           or else Key = Character'Pos ('E')
                           or else Key = 27)
               then
                  Mode := Mode_Editing;
                  Notice_Len := 0;
               elsif Is_Character
                 and then (Key = Character'Pos ('q')
                           or else Key = Character'Pos ('Q'))
               then
                  Running := False;
               elsif (Is_Character and then Key = Ctrl_L)
                 or else (not Is_Character
                          and then Key = Integer (Curses.Key_Resize))
               then
                  null;
               end if;
            end if;
         end;
      end loop;
   end Run_Unified;

   procedure Run
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean)
   is
      Dummy_Id : Token_Text;
      Init     : constant Movement_Initial_Values :=
        (Target_Id   => (Length => 0, Value => [others => ' ']),
         Date        => Selected_Day,
         From_Locus  => (Length => 0, Value => [others => ' ']),
         To_Locus    => (Length => 0, Value => [others => ' ']),
         Amount      => 0,
         Description => (Length => 0, Value => [others => ' ']));
   begin
      Run_Unified
        (Paths         => Paths,
         Selected_Day  => Selected_Day,
         Is_Correction => False,
         Init          => Init,
         New_Event_Id  => Dummy_Id,
         Committed     => Committed);
   end Run;

   procedure Run_Correction
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Init         : Movement_Initial_Values;
      New_Event_Id : out Token_Text;
      Committed    : out Boolean)
   is
   begin
      Run_Unified
        (Paths         => Paths,
         Selected_Day  => Init.Date,
         Is_Correction => True,
         Init          => Init,
         New_Event_Id  => New_Event_Id,
         Committed     => Committed);
   end Run_Correction;

   procedure Run_Split
     (Paths        : HRA_N.Application.Path_Resolver.Path_Config;
      Selected_Day : HRA_N.Core.Validity.Date_Type;
      Committed    : out Boolean)
   is
   begin
      --  Unified editor naturally supports multi-leg split movements.
      Run (Paths, Selected_Day, Committed);
   end Run_Split;

end HRA_N.UI.Record_TUI;
