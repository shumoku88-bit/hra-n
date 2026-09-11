-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Attention_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Attention_Command; use HRA_N.Application.Attention_Command;
with HRA_N.Application.Attention_Query; use HRA_N.Application.Attention_Query;
with HRA_N.Application.Review; use HRA_N.Application.Review;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Attention_CLI is

   --  Parse a due word: YYYY-MM-DD, `none`, or empty for undetermined.
   function Parse_Due
     (Text  : String;
      Due   : out Attention_Due) return Boolean
   is
      Parsed : Date_Type;
   begin
      if Text'Length = 0 then
         Due := (Kind => Due_Undetermined);
         return True;
      elsif Text = "none" then
         Due := (Kind => No_Due_Date);
         return True;
      elsif Parse_Iso_Date (Text, Parsed) then
         Due := (Kind => Due_On_Date, Due_Date => Parsed);
         return True;
      end if;
      Due := (Kind => Due_Undetermined);
      return False;
   end Parse_Due;

   procedure Display_Attention (Paths : Path_Config; Success : out Boolean) is
      View : constant Attention_View := Execute (Paths);
   begin
      Success := View.Success;
      if not View.Success then
         Put_Line ("[ERROR] " & View.Diagnostic (1 .. View.Diagnostic_Len));
         return;
      end if;
      Put_Line ("============================================================");
      Put_Line (" HRA-N Attention (" & Natural'Image (View.Count) & " open)");
      Put_Line ("============================================================");
      for I in 1 .. View.Count loop
         Put_Line
           ("  " & View.Rows (I).Id.Value (1 .. View.Rows (I).Id.Length)
            & "  [" & Due_Label (View.Rows (I).Due) & "]  "
            & View.Rows (I).Context.Value (1 .. View.Rows (I).Context.Length));
      end loop;
   end Display_Attention;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean)
   is
   begin
      Success := False;
      if Rem_Args = 0 then
         Display_Attention (Paths, Success);
         return;
      end if;

      declare
         Sub : constant String := Ada.Command_Line.Argument (Command_Idx + 1);
      begin
         if Sub = "raise" then
            if Rem_Args < 2 then
               Put_Line ("Usage: hra-n attention raise ""<context>"" [YYYY-MM-DD|none]");
               return;
            end if;
            declare
               Ctx_Str : constant String :=
                 Ada.Command_Line.Argument (Command_Idx + 2);
               Due_Str : constant String :=
                 (if Rem_Args >= 3
                  then Ada.Command_Line.Argument (Command_Idx + 3)
                  else "");
               Due : Attention_Due;
            begin
               if Ctx_Str'Length = 0
                 or else Ctx_Str'Length > Max_Description_Length
               then
                  Put_Line ("[ERROR] Context must be 1..512 characters");
                  return;
               elsif not Parse_Due (Due_Str, Due) then
                  Put_Line ("[ERROR] Due must be YYYY-MM-DD or none");
                  return;
               end if;
               declare
                  Intent : constant Raise_Intent :=
                    (Context => Make_Description (Ctx_Str),
                     Due     => Due);
                  Prop_Res : constant Proposal_Result :=
                    Propose_Raise (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Line ("[ERROR] Raise rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     return;
                  end if;
                  declare
                     Receipt : constant Attention_Receipt :=
                       Commit (Prop_Res.Proposal);
                  begin
                     if Receipt.Success then
                        Put_Line ("============================================================");
                        Put_Line (" [OK] Raised Attention: " &
                                  Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                        Put_Line ("      SNAPSHOT: " &
                                  Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                        Put_Line ("============================================================");
                        Success := True;
                     else
                        Put_Line ("[ERROR] Raise commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               end;
            end;
         elsif Sub = "resolve" or else Sub = "drop" then
            if Rem_Args < 2 then
               Put_Line ("Usage: hra-n attention (resolve|drop) <ID> [YYYY-MM-DD]");
               return;
            end if;
            declare
               Id_Str   : constant String :=
                 Ada.Command_Line.Argument (Command_Idx + 2);
               Date_Val : Date_Type := Get_System_Date;
            begin
               if Id_Str'Length = 0 or else Id_Str'Length > Max_Token_Length then
                  Put_Line ("[ERROR] Invalid attention identity");
                  return;
               end if;
               if Rem_Args >= 3 then
                  declare
                     Date_Arg : constant String :=
                       Ada.Command_Line.Argument (Command_Idx + 3);
                     Parsed_D : Date_Type;
                  begin
                     if not Parse_Iso_Date (Date_Arg, Parsed_D) then
                        Put_Line ("[ERROR] Knowledge date must be YYYY-MM-DD");
                        return;
                     end if;
                     Date_Val := Parsed_D;
                  end;
               end if;
               declare
                  Intent : constant Close_Intent :=
                    (Target_Id => Make_Token (Id_Str),
                     Kind      =>
                       (if Sub = "resolve" then Closure_Resolved
                        else Closure_Dropped),
                     Known_On  => Date_Val);
                  Prop_Res : constant Proposal_Result :=
                    Propose_Close (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Line ("[ERROR] Close rejected: " &
                               Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     return;
                  end if;
                  declare
                     Receipt : constant Attention_Receipt :=
                       Commit (Prop_Res.Proposal);
                  begin
                     if Receipt.Success then
                        Put_Line ("============================================================");
                        Put_Line (" [OK] Closed Attention: " & Id_Str);
                        Put_Line ("      SNAPSHOT: " &
                                  Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                        Put_Line ("============================================================");
                        Success := True;
                     else
                        Put_Line ("[ERROR] Close commit rejected: " &
                                  Receipt.Error (1 .. Receipt.Error_Len));
                     end if;
                  end;
               end;
            end;
         else
            Put_Line ("Usage: hra-n attention [raise|resolve|drop]");
         end if;
      end;
   end Dispatch;

end HRA_N.UI.Attention_CLI;
