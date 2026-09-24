-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Policy_CLI
-------------------------------------------------------------------------------

with Ada.Command_Line;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Policy_Command; use HRA_N.Application.Policy_Command;
with HRA_N.Application.Policy_Query;   use HRA_N.Application.Policy_Query;
with HRA_N.Application.Review;         use HRA_N.Application.Review;
with HRA_N.Core.Accounting_Role;       use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types;                 use HRA_N.Core.Types;
with HRA_N.Core.Validity;              use HRA_N.Core.Validity;
with HRA_N.Storage.Loam_Accounting_Role_Writer;
with HRA_N.UI.Output;                  use HRA_N.UI.Output;

package body HRA_N.UI.Policy_CLI is

   function Role_Str (Role : Accounting_Role) return String is
     (case Role is
        when Role_Asset     => "ASSET    ",
        when Role_Liability => "LIABILITY",
        when Role_Equity    => "EQUITY   ",
        when Role_Income    => "INCOME   ",
        when Role_Expense   => "EXPENSE  ");

   function Parse_Role (S : String; Role : out Accounting_Role) return Boolean is
   begin
      if S = "ASSET" or else S = "asset" then
         Role := Role_Asset;
         return True;
      elsif S = "LIABILITY" or else S = "liability" then
         Role := Role_Liability;
         return True;
      elsif S = "EQUITY" or else S = "equity" then
         Role := Role_Equity;
         return True;
      elsif S = "INCOME" or else S = "income" then
         Role := Role_Income;
         return True;
      elsif S = "EXPENSE" or else S = "expense" then
         Role := Role_Expense;
         return True;
      else
         Role := Role_Asset;
         return False;
      end if;
   end Parse_Role;

   procedure Handle_Role_Command
     (Paths     : Path_Config;
      Start_Arg : Positive)
   is
      Total_Args : constant Natural := Ada.Command_Line.Argument_Count;
      Rem_Args   : constant Natural :=
        (if Total_Args >= Start_Arg then Total_Args - Start_Arg + 1 else 0);
   begin
      if Rem_Args > 0
        and then Ada.Command_Line.Argument (Start_Arg) = "assign"
      then
         --  assign <locus> <role> [date] [replaces-id]
         if Rem_Args < 3 then
            Put_Error_Line ("Usage: hra-n role assign <locus> <role> [date] [replaces-id]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            Locus_Str : constant String := Ada.Command_Line.Argument (Start_Arg + 1);
            Role_Str_Arg : constant String := Ada.Command_Line.Argument (Start_Arg + 2);
            Role_Val  : Accounting_Role;
            Date_Val  : Date_Type := Get_System_Date;
            Has_Rep   : Boolean := False;
            Rep_Str   : String (1 .. 64) := [others => ' '];
            Rep_Len   : Natural := 0;
            Intent    : Role_Intent;
         begin
            if not Parse_Role (Role_Str_Arg, Role_Val) then
               Put_Error_Line ("hra-n role assign: invalid accounting role: " & Role_Str_Arg);
               Put_Error_Line ("Valid roles: ASSET, LIABILITY, EQUITY, INCOME, EXPENSE");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            if Rem_Args >= 4 then
               declare
                  D_Str : constant String := Ada.Command_Line.Argument (Start_Arg + 3);
               begin
                  if not Parse_Iso_Date (D_Str, Date_Val) then
                     Put_Error_Line ("hra-n role assign: invalid ISO date: " & D_Str);
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;
               end;
            end if;

            if Rem_Args >= 5 then
               declare
                  R_Arg : constant String := Ada.Command_Line.Argument (Start_Arg + 4);
               begin
                  Has_Rep := True;
                  Rep_Len := Natural'Min (R_Arg'Length, Rep_Str'Length);
                  Rep_Str (1 .. Rep_Len) := R_Arg (R_Arg'First .. R_Arg'First + Rep_Len - 1);
               end;
            end if;

            Intent :=
              (Id             => (Length => 0, Value => [others => ' ']),
               Locus          => (Token => Make_Token (Locus_Str)),
               Role           => Role_Val,
               Effective_From => Date_Val,
               Has_Replaces   => Has_Rep,
               Replaces_Id    => Make_Token (Rep_Str (1 .. Rep_Len)));

            if Paths.Is_Canonical then
               declare
                  Data_Dir : constant String := Data_Dir_Str (Paths);
                  Draft : constant
                    HRA_N.Storage.Loam_Accounting_Role_Writer.Role_Draft :=
                      (Locus => (Token => Make_Token (Locus_Str)),
                       Role  => Role_Val);
                  Pub_Res : constant
                    HRA_N.Storage.Loam_Accounting_Role_Writer.Publish_Result :=
                      HRA_N.Storage.Loam_Accounting_Role_Writer.Publish_Role
                        (Data_Dir, Draft);
               begin
                  if not Pub_Res.Success then
                     Put_Error_Line ("hra-n role assign rejected:");
                     if Pub_Res.Error_Len > 0 then
                        Put_Error_Line ("  " & Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
                     end if;
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;

                  Put_Line ("[OK] Committed Canonical Role Assignment: " &
                            Locus_Str & " -> " & Role_Str_Arg);
                  Put_Line ("AUTHORITY: accounting-role.loam");
               end;
            else
               declare
                  Prop_Res : constant Proposal_Result :=
                    Propose_Role (Paths, Intent);
               begin
                  if not Prop_Res.Success then
                     Put_Error_Line ("hra-n role assign rejected:");
                     if Prop_Res.Error_Len > 0 then
                        Put_Error_Line ("  " & Prop_Res.Error (1 .. Prop_Res.Error_Len));
                     end if;
                     Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                     return;
                  end if;

                  declare
                     Receipt : constant Policy_Receipt :=
                       Commit (Prop_Res.Proposal);
                  begin
                     if not Receipt.Success then
                        Put_Error_Line ("hra-n role assign commit failed:");
                        if Receipt.Error_Len > 0 then
                           Put_Error_Line ("  " & Receipt.Error (1 .. Receipt.Error_Len));
                        end if;
                        Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                        return;
                     end if;

                     Put_Line ("[OK] Committed Role Assignment: " &
                               Receipt.Primary_Id (1 .. Receipt.Primary_Len));
                     Put_Line ("SNAPSHOT: " &
                               Receipt.Snapshot_Id (1 .. Receipt.Snapshot_Len));
                  end;
               end;
            end if;
         end;
      else
         --  Listing active roles
         declare
            Has_As_Of : Boolean := False;
            As_Of     : Date_Type := Get_System_Date;
            Arg_Idx   : Positive := Start_Arg;
         begin
            if Rem_Args > 0 and then Ada.Command_Line.Argument (Start_Arg) = "list" then
               Arg_Idx := Start_Arg + 1;
            end if;

            while Arg_Idx <= Total_Args loop
               declare
                  Arg : constant String := Ada.Command_Line.Argument (Arg_Idx);
               begin
                  if Arg = "--as-of" and then Arg_Idx < Total_Args then
                     declare
                        D_Str : constant String := Ada.Command_Line.Argument (Arg_Idx + 1);
                     begin
                        if not Parse_Iso_Date (D_Str, As_Of) then
                           Put_Error_Line ("hra-n role: invalid as-of date: " & D_Str);
                           Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                           return;
                        end if;
                        Has_As_Of := True;
                        Arg_Idx := Arg_Idx + 1;
                     end;
                  end if;
               end;
               Arg_Idx := Arg_Idx + 1;
            end loop;

            declare
               View : constant Role_View :=
                 Execute_Role_Query (Paths, As_Of => As_Of, Has_As_Of => Has_As_Of);
            begin
               if View.Status = Query_Rejected then
                  Put_Error_Line ("hra-n: role query rejected");
                  if View.Diagnostic_Len > 0 then
                     Put_Error_Line ("       " & View.Diagnostic (1 .. View.Diagnostic_Len));
                  end if;
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
               end if;

               Put_Line ("============================================================");
               Put_Line (" HRA-N Accounting Roles");
               Put_Line (" Snapshot : " & View.Snapshot (1 .. View.Snapshot_Len));
               if View.Has_As_Of then
                  Put_Line (" As-Of    : " & Format_Iso_Date (View.As_Of_Date));
               end if;
               Put_Line ("============================================================");

               if View.Row_Count = 0 then
                  Put_Line ("No accounting roles assigned.");
               else
                  Put_Line ("  ID      LOCUS          ROLE        EFFECTIVE     REPLACES");
                  Put_Line (" ------------------------------------------------------------");
                  for I in 1 .. View.Row_Count loop
                     declare
                        Row     : constant Role_View_Row := View.Rows (I);
                        Id_Str  : constant String := Row.Id.Value (1 .. Row.Id.Length);
                        Loc_Str : constant String := Row.Locus.Value (1 .. Row.Locus.Length);
                        Rep_Str : constant String :=
                          (if Row.Has_Replaces then Row.Replaces.Value (1 .. Row.Replaces.Length) else "-");
                     begin
                        Put_Line ("  " & Pad_Right (Id_Str, 7) & " " &
                                  Pad_Right (Loc_Str, 14) & " " &
                                  Role_Str (Row.Role) & "  " &
                                  Format_Iso_Date (Row.Effective_From) & "    " &
                                  Rep_Str);
                     end;
                  end loop;
                  Put_Line (" ------------------------------------------------------------");
                  Put_Line (" Total: " & Natural'Image (View.Row_Count) & " roles");
               end if;
               Put_Line ("============================================================");
            end;
         end;
      end if;
   end Handle_Role_Command;

end HRA_N.UI.Policy_CLI;
