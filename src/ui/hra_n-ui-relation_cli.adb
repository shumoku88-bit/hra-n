-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Relation_CLI
-------------------------------------------------------------------------------

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;
with HRA_N.Storage.Relation_Reader; use HRA_N.Storage.Relation_Reader;
with HRA_N.Application.Relation_Frontier;
use HRA_N.Application.Relation_Frontier;
with HRA_N.UI.Output; use HRA_N.UI.Output;

package body HRA_N.UI.Relation_CLI is

   function Token_Image (Value : Token_Text) return String is
     (Value.Value (1 .. Value.Length));

   function Endpoint_Image (Endpoint : Relation_Endpoint) return String is
     (case Endpoint.Kind is
        when Endpoint_Household => "household",
        when Endpoint_External  => Token_Image (Endpoint.External_Id));

   procedure Display_Relations
     (Authority_Dir : String;
      Manifest      : Manifest_Record;
      Events        : Event_Vectors.Vector;
      Success       : out Boolean)
   is
   begin
      Success := False;
      if not Manifest (Family_Relation_Unit).Present
        or else not Manifest (Family_Relation_Discharge).Present
      then
         Put_Error_Line ("hra-n: relation families are absent from CURRENT");
         return;
      end if;

      declare
         Unit_Item : constant Manifest_Item :=
           Manifest (Family_Relation_Unit);
         Discharge_Item : constant Manifest_Item :=
           Manifest (Family_Relation_Discharge);
         Unit_Result : constant Unit_Read_Result :=
           Read_Relation_Unit_File
             (Authority_Dir & "/" &
              Unit_Item.Rel_Path (1 .. Unit_Item.Path_Len));
         Discharge_Result : constant Discharge_Read_Result :=
           Read_Relation_Discharge_File
             (Authority_Dir & "/" &
              Discharge_Item.Rel_Path (1 .. Discharge_Item.Path_Len));
         All_Resolved : Boolean := True;
      begin
         if not Unit_Result.Success then
            Put_Error_Line
              ("hra-n: relation units failed to parse: " &
               Unit_Result.Error_Reason (1 .. Unit_Result.Error_Len));
            return;
         elsif not Discharge_Result.Success then
            Put_Error_Line
              ("hra-n: relation discharges failed to parse: " &
               Discharge_Result.Error_Reason
                 (1 .. Discharge_Result.Error_Len));
            return;
         end if;

         Put_Line ("============================================================");
         Put_Line (" HRA-N Open Relation Frontier");
         Put_Line ("============================================================");

         if Unit_Result.Memory.Count = 0 then
            Put_Line ("No retained relation units. Outstanding state is empty.");
         else
            for I in 1 .. Unit_Result.Memory.Count loop
               declare
                  Unit : constant Relation_Unit :=
                    Unit_Result.Memory.Units (I);
                  Projection : Outstanding_Result;
                  Id_Text : constant String := Token_Image (Unit.Id);
               begin
                  Project_Outstanding
                    (Events,
                     Unit_Result.Memory,
                     Discharge_Result.Memory,
                     Unit.Id,
                     Projection);

                  case Projection.State is
                     when Relation_Open =>
                        Put_Line
                          ("[OPEN] " & Id_Text & "  " &
                           Endpoint_Image (Unit.Debtor) & " -> " &
                           Endpoint_Image (Unit.Creditor));
                        Put_Line
                          ("       outstanding=" &
                           Trim (Projection.Outstanding_Quantity'Image,
                                 Ada.Strings.Both) & "/" &
                           Trim (Projection.Original_Quantity'Image,
                                 Ada.Strings.Both) & " " &
                           Token_Image (Projection.Measure.Token));
                     when Relation_Discharged =>
                        Put_Line
                          ("[DISCHARGED] " & Id_Text & "  " &
                           Endpoint_Image (Unit.Debtor) & " -> " &
                           Endpoint_Image (Unit.Creditor));
                     when Evidence_Unresolved =>
                        Put_Line
                          ("[UNRESOLVED] " & Id_Text &
                           " (conflicting or inadmissible active evidence)");
                        All_Resolved := False;
                     when Target_Absent =>
                        Put_Line
                          ("[UNRESOLVED] " & Id_Text &
                           " (identity could not be resolved)");
                        All_Resolved := False;
                  end case;
               end;
            end loop;
         end if;

         Put_Line ("------------------------------------------------------------");
         Put_Line
           ("Raw provenance: " &
            Trim (Unit_Result.Memory.Count'Image, Ada.Strings.Both) &
            " units, " &
            Trim (Discharge_Result.Memory.Count'Image, Ada.Strings.Both) &
            " discharge rows");
         Success := All_Resolved;
      end;
   end Display_Relations;

end HRA_N.UI.Relation_CLI;
