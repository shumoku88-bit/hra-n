------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Canonical_Authority
------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Exceptions;

use type Ada.Directories.File_Kind;

package body HRA_N.Application.Canonical_Authority is

   function Probe
     (Root_Path : String) return Authority_Probe
   is
      Result : Authority_Probe :=
        (State          => Probe_Failed,
         Diagnostic     => [others => ' '],
         Diagnostic_Len => 0);

      procedure Set_Failure (Reason : String) is
         Len : constant Natural :=
           Natural'Min (Reason'Length, Result.Diagnostic'Length);
      begin
         Result.State := Probe_Failed;
         Result.Diagnostic := [others => ' '];
         Result.Diagnostic_Len := Len;
         if Len > 0 then
            Result.Diagnostic (1 .. Len) :=
              Reason (Reason'First .. Reason'First + Len - 1);
         end if;
      end Set_Failure;
   begin
      if Root_Path'Length = 0 then
         Set_Failure ("root path is empty");
         return Result;
      end if;

      if not Ada.Directories.Exists (Root_Path) then
         Set_Failure ("root directory does not exist: " & Root_Path);
         return Result;
      end if;

      if Ada.Directories.Kind (Root_Path) /= Ada.Directories.Directory then
         Set_Failure ("root path is not a directory: " & Root_Path);
         return Result;
      end if;

      declare
         Scheduled_Path : constant String :=
           Ada.Directories.Compose (Root_Path, "scheduled.loam");
         Actual_Path    : constant String :=
           Ada.Directories.Compose (Root_Path, "actual.loam");
         Policy_Path    : constant String :=
           Ada.Directories.Compose (Root_Path, "locus-admission.loam");

         Has_Scheduled  : constant Boolean :=
           Ada.Directories.Exists (Scheduled_Path);
         Has_Actual     : constant Boolean :=
           Ada.Directories.Exists (Actual_Path);
         Has_Policy     : constant Boolean :=
           Ada.Directories.Exists (Policy_Path);
      begin
         if Has_Scheduled or else Has_Actual or else Has_Policy then
            Result.State := Canonical_Present;
         else
            Result.State := Legacy_Only;
         end if;
         return Result;
      end;
   exception
      when E : others =>
         Set_Failure
           ("probe error: "
            & Ada.Exceptions.Exception_Name (E) & " - "
            & Ada.Exceptions.Exception_Message (E));
         return Result;
   end Probe;

end HRA_N.Application.Canonical_Authority;
