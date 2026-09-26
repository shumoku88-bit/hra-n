-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Attention_Query
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Loam_Attention_Reader;
with HRA_N.Application.Canonical_Authority;
with Ada.Directories;

package body HRA_N.Application.Attention_Query is

   function Due_Label (Due : Attention_Due) return String is
     (case Due.Kind is
         when Due_On_Date    => "due " & Format_Iso_Date (Due.Due_Date),
         when No_Due_Date    => "no due date",
         when Due_Undetermined => "due unknown");

   function Execute (Paths : Path_Config) return Attention_View is
      use HRA_N.Application.Frontend_Types;

      View   : Attention_View;
      Memory : Attention_Memory;
      Canonical : HRA_N.Storage.Loam_Attention_Reader.Read_Result;
      use HRA_N.Application.Canonical_Authority;

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, View.Diagnostic'Length);
      begin
         View.Diagnostic_Len := Len;
         View.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;
   begin
      if not Paths.Resolution_Ok then
         Set_Diagnostic (Paths.Error_Reason (1 .. Paths.Error_Len));
         return View;
      end if;

      declare
         Authority : constant Authority_Probe := Probe (Data_Dir_Str (Paths));
         File_Path : constant String :=
           Ada.Directories.Compose (Data_Dir_Str (Paths), "attention.loam");
      begin
         if Authority.State = Probe_Failed then
            Set_Diagnostic ("Attention authority: " & Authority.Diagnostic (1 .. Authority.Diagnostic_Len));
            return View;
         end if;
         Canonical := HRA_N.Storage.Loam_Attention_Reader.Read_File (File_Path);
         if not Canonical.Success then
            Set_Diagnostic ("attention.loam: " & Canonical.Diagnostic (1 .. Canonical.Diagnostic_Len));
            return View;
         elsif Canonical.Present then
            View.Source := Canonical_Attention;
            View.Availability := Attention_Available;
            View.Snapshot := (Kind => Snapshot_Unversioned);
            Memory := Canonical.Memory;
         else
            View.Source := Canonical_Unavailable;
            View.Status := Query_Partial;
            View.Success := True;
            Set_Diagnostic ("attention.loam unavailable");
            return View;
         end if;
      end;

      for I in 1 .. Memory.Item_Count loop
         if not Has_Closure (Memory, Memory.Items (I).Id) then
            if View.Count >= Max_Query_Rows then
               Set_Diagnostic ("Attention view capacity exceeded");
               return View;
            end if;
            View.Count := View.Count + 1;
            View.Rows (View.Count) :=
              (Id      => Memory.Items (I).Id,
               Context => Memory.Items (I).Context,
               Due     => Memory.Items (I).Due);
         end if;
      end loop;

      View.Success := True;
      View.Status := Query_Complete;
      return View;
   end Execute;

end HRA_N.Application.Attention_Query;
