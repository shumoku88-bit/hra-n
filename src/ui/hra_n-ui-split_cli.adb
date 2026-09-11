-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Split_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Movement_Command; use HRA_N.Application.Movement_Command;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Split_CLI is

   function Parse_Integer_Text (Text : String; Value : out Long_Long_Integer) return Boolean is
      Sign  : Long_Long_Integer := 1;
      First : Positive := Text'First;
      Res   : Long_Long_Integer := 0;
   begin
      Value := 0;
      if Text'Length = 0 then
         return False;
      end if;
      if Text (First) = '-' then
         Sign := -1;
         First := First + 1;
      elsif Text (First) = '+' then
         First := First + 1;
      end if;
      if First > Text'Last then
         return False;
      end if;
      for I in First .. Text'Last loop
         if Text (I) not in '0' .. '9' then
            return False;
         end if;
         Res := Res * 10 + Long_Long_Integer (Character'Pos (Text (I)) - Character'Pos ('0'));
      end loop;
      Value := Res * Sign;
      return True;
   end Parse_Integer_Text;

   function Token_Text_Ok (Text : String; Allow_Colon : Boolean) return Boolean is
   begin
      if Text'Length = 0 or else Text'Length > Max_Token_Length then
         return False;
      end if;
      for I in Text'Range loop
         if Text (I) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR | '"' then
            return False;
         elsif not Allow_Colon and then Text (I) = ':' then
            return False;
         end if;
      end loop;
      return True;
   end Token_Text_Ok;

   --  Split one change word following the journal flow grammar: the amount
   --  is the integer after the last colon (measure defaults to jpy), or
   --  the integer between the last two colons with an explicit measure.
   procedure Parse_Change
     (Text    : String;
      Locus   : out Token_Text;
      Measure : out Token_Text;
      Amount  : out Quanta_Type;
      Valid   : out Boolean)
   is
      Last_Colon : Natural := 0;
      Prev_Colon : Natural := 0;
      Amt_Val    : Long_Long_Integer;
   begin
      Locus := Make_Token ("");
      Measure := Make_Token ("jpy");
      Amount := Zero_Quanta;
      Valid := False;
      for I in Text'Range loop
         if Text (I) = ':' then
            Prev_Colon := Last_Colon;
            Last_Colon := I;
         end if;
      end loop;
      if Last_Colon = 0 then
         return;
      end if;
      if Parse_Integer_Text (Text (Last_Colon + 1 .. Text'Last), Amt_Val) then
         if not Token_Text_Ok (Text (Text'First .. Last_Colon - 1), True) then
            return;
         end if;
         Locus := Make_Token (Text (Text'First .. Last_Colon - 1));
      elsif Prev_Colon > Text'First
        and then Parse_Integer_Text
          (Text (Prev_Colon + 1 .. Last_Colon - 1), Amt_Val)
        and then Token_Text_Ok (Text (Last_Colon + 1 .. Text'Last), False)
      then
         if not Token_Text_Ok (Text (Text'First .. Prev_Colon - 1), True) then
            return;
         end if;
         Locus := Make_Token (Text (Text'First .. Prev_Colon - 1));
         Measure := Make_Token (Text (Last_Colon + 1 .. Text'Last));
      else
         return;
      end if;
      if Amt_Val = 0
        or else Amt_Val > Long_Long_Integer (Quanta_Type'Last)
        or else Amt_Val < Long_Long_Integer (Quanta_Type'First)
      then
         Valid := False;
         return;
      end if;
      Amount := Quanta_Type (Amt_Val);
      Valid := True;
   end Parse_Change;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
      Date_Val  : Date_Type := HRA_N.Application.Review.Get_System_Date;
      Desc_Val  : String (1 .. 128) := [others => ' '];
      Desc_Len  : Natural := 0;
      Arg_Start : Positive := Command_Idx + 1;
      Intent    : Record_Split_Intent;
   begin
      Success := False;
      Intent.Count := 0;
      Intent.Valid_On := Date_Val;
      Intent.Description := Make_Token ("");

      if Rem_Args >= 1 then
         declare
            First : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
            Parsed_D : Date_Type;
         begin
            if Parse_Iso_Date (First, Parsed_D) then
               Date_Val := Parsed_D;
               Intent.Valid_On := Date_Val;
               Arg_Start := Command_Idx + 2;
            end if;
         end;
      end if;

      for A in Arg_Start .. Command_Idx + Rem_Args loop
         if Ada.Command_Line.Argument (A) = "--desc" then
            if A = Command_Idx + Rem_Args then
               Put_Line ("Usage: hra-n split [YYYY-MM-DD] [--desc TEXT] LOCUS:AMOUNT[:MEASURE] ...");
               return;
            end if;
            declare
               Text : constant String := Ada.Command_Line.Argument (A + 1);
               L : constant Natural := Natural'Min (Text'Length, Desc_Val'Length);
            begin
               if Desc_Len > 0 then
                  Put_Line ("[ERROR] Duplicate --desc flag");
                  return;
               elsif Text'Length = 0 then
                  Put_Line ("[ERROR] Empty --desc text");
                  return;
               end if;
               Desc_Len := L;
               Desc_Val (1 .. L) := Text (Text'First .. Text'First + L - 1);
            end;
         end if;
      end loop;

      for A in Arg_Start .. Command_Idx + Rem_Args loop
         declare
            Word : constant String := Ada.Command_Line.Argument (A);
         begin
            if Word = "--desc" then
               null;
            elsif A > Arg_Start
              and then Ada.Command_Line.Argument (A - 1) = "--desc"
            then
               null;
            else
               declare
                  Locus   : Token_Text;
                  Measure : Token_Text;
                  Amount  : Quanta_Type;
                  Ok      : Boolean;
               begin
                  Parse_Change (Word, Locus, Measure, Amount, Ok);
                  if not Ok then
                     Put_Line ("[ERROR] Malformed split change: " & Word);
                     return;
                  elsif Natural (Intent.Count) = Max_Split_Changes then
                     Put_Line ("[ERROR] Too many split changes");
                     return;
                  end if;
                  Intent.Count := Intent.Count + 1;
                  Intent.Changes (Positive (Intent.Count)) :=
                    (Locus   => (Token => Locus),
                     Measure => (Token => Measure),
                     Amount  => Amount);
               end;
            end if;
         end;
      end loop;

      if Intent.Count < 2 then
         Put_Line ("Usage: hra-n split [YYYY-MM-DD] [--desc TEXT] LOCUS:AMOUNT[:MEASURE] ...");
         return;
      end if;

      Intent.Description := Make_Token (Desc_Val (1 .. Desc_Len));
      declare
         Prop_Res : constant Proposal_Result :=
           Propose_Split (Paths, Intent);
      begin
         if not Prop_Res.Success then
            Put_Line ("[ERROR] Split rejected: " &
                      Prop_Res.Error (1 .. Prop_Res.Error_Len));
            return;
         end if;
         declare
            Receipt : constant Movement_Receipt :=
              Commit (Prop_Res.Proposal);
         begin
            if Receipt.Success then
               Put_Line ("============================================================");
               Put_Line (" [OK] Committed Split: " &
                         Receipt.Primary_Id (1 .. Receipt.Primary_Len));
               Put_Line ("      SNAPSHOT: " &
                         Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
               Put_Line ("      DATE:     " & Format_Iso_Date (Date_Val));
               if Desc_Len > 0 then
                  Put_Line ("      DESC:     " & Desc_Val (1 .. Desc_Len));
               end if;
               Put_Line ("============================================================");
               Success := True;
            else
               Put_Line ("[ERROR] Split commit rejected: " &
                         Receipt.Error (1 .. Receipt.Error_Len));
            end if;
         end;
      end;
   end Dispatch;

end HRA_N.UI.Split_CLI;
