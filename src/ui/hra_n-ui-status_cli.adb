------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Status_CLI
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;              use Ada.Strings.Fixed;
with HRA_N.Core.Types;               use HRA_N.Core.Types;
with HRA_N.Core.Event;               use HRA_N.Core.Event;
with HRA_N.Core.Scheduled;           use HRA_N.Core.Scheduled;
with HRA_N.Core.Coverage;            use HRA_N.Core.Coverage;
with HRA_N.Core.Accounting_Role;     use HRA_N.Core.Accounting_Role;
with HRA_N.Application.Statement;    use HRA_N.Application.Statement;
with HRA_N.UI.Output;                use HRA_N.UI.Output;
with HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader;

package body HRA_N.UI.Status_CLI is

   function Img (Value : Long_Long_Integer) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   procedure Display_Status
     (Paths   : Path_Config;
      Events  : Event_Vectors.Vector;
      Success : out Boolean)
   is
      Statement : Statement_Report;
      PR        : constant HRA_N.Storage.Policy_Reader.Policy_Result :=
        HRA_N.Storage.Policy_Reader.Read_Policy_File (Policy_Path_Str (Paths));
      SR        : constant HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result :=
        HRA_N.Storage.Scheduled_Journal_Reader.Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
   begin
      Success := False;

      if not PR.Success or else not SR.Success then
         Put_Error_Line ("hra-n: HRA status evidence could not be acquired");
         return;
      end if;

      Generate_Report (Events, PR.Roles, Statement);

      Put_Line ("============================================================");
      Put_Line (" HRA-N Household Status (Canonical Storage)");
      Put_Line ("============================================================");
      Put_Line ("Authority : HEALTHY");
      Put_Line ("Events    : " & Trim (Events.Length'Image, Ada.Strings.Both));
      if Statement.Summary.Status = Statement_Complete then
         Put_Line ("Statement : COMPLETE");
         Put_Line ("Net worth : " & Img (Net_Worth (Statement.Summary)));
         Put_Line ("Savings   : " & Img (Net_Savings (Statement.Summary)));
      else
         Put_Line ("Statement : PARTIAL (epistemic frontier visible)");
         Put_Line ("Unresolved loci: " &
           Trim (Statement.Unresolved_Count'Image, Ada.Strings.Both));
      end if;

      --  Compute coverage balances directly from events
      Put_Line ("------------------------------------------------------------");
      Put_Line ("Canonical Zero-Origin Balances:");
      for C in 1 .. Coordinate_Count (PR.Coverage) loop
         declare
            Coord     : constant Coordinate_Type := Coordinate_At (PR.Coverage, C);
            Coord_Str : constant String :=
              Coord.Locus.Token.Value (1 .. Coord.Locus.Token.Length);
            Bal       : Long_Long_Integer := 0;
         begin
            for E of Events loop
               for I in 1 .. Effect_Count (E) loop
                  declare
                     Eff     : constant Effect := Effect_At (E, I);
                     Loc_Str : constant String :=
                       Eff.Locus.Token.Value (1 .. Eff.Locus.Token.Length);
                  begin
                     if Loc_Str = Coord_Str then
                        Bal := Bal + Long_Long_Integer (Eff.Amount.Quanta);
                     end if;
                  end;
               end loop;
            end loop;

            Put_Line ("  " & Pad_Right (Coord_Str, 15) & ": " &
                      Pad_Left (Format_Amount (Quanta_Type (Bal)), 12) & " jpy");
         end;
      end loop;

      --  Count open scheduled items
      declare
         Open_Count : Natural := 0;
      begin
         for I in 1 .. SR.Lifecycle.Sched_Count loop
            if Is_Current_Open (SR.Lifecycle, SR.Lifecycle.Sched_Items (I).Id) then
               Open_Count := Open_Count + 1;
            end if;
         end loop;

         Put_Line ("------------------------------------------------------------");
         Put_Line ("Scheduled Obligations: " & Trim (Open_Count'Image, Ada.Strings.Both) & " open");
         Put_Line ("============================================================");
      end;

      Success := True;
   end Display_Status;

end HRA_N.UI.Status_CLI;
