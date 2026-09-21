-------------------------------------------------------------------------------
--  HRA-N: Read-only LOAM canonical Actual qualification adapter
--
--  This executable owns no household authority and exposes no write path.
--  It reports only structural qualification metadata for one normalized
--  LOAM Actual document.
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Containers;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO;       use Ada.Text_IO;

with HRA_N.Core.Description;
with HRA_N.Core.Event;    use HRA_N.Core.Event;
with HRA_N.Core.Validity;
with HRA_N.Storage.Loam_Actual_Reader;
use HRA_N.Storage.Loam_Actual_Reader;

procedure HRA_N_Loam_Qualify is

   function Natural_Str (Value : Natural) return String is
   begin
      return Trim (Natural'Image (Value), Both);
   end Natural_Str;

   procedure Meta (Name, Value : String) is
   begin
      Put_Line
        ("HRAQ1" & ASCII.HT & "meta" & ASCII.HT & Name & ASCII.HT & Value);
   end Meta;

   procedure Scalar (Name, Value : String) is
   begin
      Put_Line
        ("HRAQ1" & ASCII.HT & "scalar" & ASCII.HT & Name & ASCII.HT &
         "count" & ASCII.HT & Value);
   end Scalar;

   procedure Fail (Result : Loam_Actual_Result) is
   begin
      if Result.Error_Line > 0 then
         Put (Standard_Error,
              "hra-n-loam-qualify: rejected line" &
              Natural'Image (Result.Error_Line));
      else
         Put (Standard_Error, "hra-n-loam-qualify: rejected input");
      end if;

      if Result.Error_Len > 0 then
         Put
           (Standard_Error,
            ": " & Result.Error_Reason (1 .. Result.Error_Len));
      end if;
      New_Line (Standard_Error);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Fail;

begin
   if Ada.Command_Line.Argument_Count /= 1 then
      Put_Line
        (Standard_Error,
         "Usage: hra-n-loam-qualify /path/to/actual.loam");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Path   : constant String := Ada.Command_Line.Argument (1);
      Result : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
   begin
      if not Result.Success then
         Fail (Result);
         return;
      end if;

      declare
         Event_Count       : constant Natural :=
           Natural (Result.Events.Length);
         Effect_Total      : Natural := 0;
         Retained_Key_Total : Natural := 0;
      begin
         for Ev of Result.Events loop
            Effect_Total := Effect_Total + Natural (Effect_Count (Ev));
            for I in 1 .. Effect_Count (Ev) loop
               if Effect_At (Ev, Effect_Index_Type (I)).Key.Present then
                  Retained_Key_Total := Retained_Key_Total + 1;
               end if;
            end loop;
         end loop;

         --  Do not emit household amounts, loci, measures, descriptions, or
         --  identities. This adapter is qualification evidence, not a report.
         Meta ("schema", "1");
         Meta ("implementation", "hra-n");
         Meta ("source_schema", "LOAM-NORMALIZED-ACTUAL-1");
         Scalar ("events", Natural_Str (Event_Count));
         Scalar ("effects", Natural_Str (Effect_Total));
         Scalar ("retained_effect_keys", Natural_Str (Retained_Key_Total));
         Scalar
           ("validity_entries",
            Natural_Str
              (Natural (HRA_N.Core.Validity.Entry_Count (Result.Validities))));
         Scalar
           ("description_entries",
            Natural_Str
              (Natural
                 (HRA_N.Core.Description.Entry_Count (Result.Descriptions))));
         Meta ("status", "complete");
      end;
   end;
end HRA_N_Loam_Qualify;
