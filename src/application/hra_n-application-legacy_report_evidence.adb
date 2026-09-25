with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;
with HRA_N.Storage.Legacy_Admission;

package body HRA_N.Application.Legacy_Report_Evidence is
   procedure Read_Admitted
     (Paths   : Path_Config;
      Journal : out Journal_Result;
      Policy  : out Policy_Result)
   is
   begin
      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      declare
         Scheduled : constant Scheduled_Journal_Result :=
           Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));
         Rejection : constant String :=
           HRA_N.Storage.Legacy_Admission.Failure (Journal, Policy, Scheduled);
      begin
         if Rejection'Length > 0 then
            Journal.Success := False;
            Journal.Error_Len := Natural'Min (Rejection'Length, Journal.Error_Reason'Length);
            Journal.Error_Reason (1 .. Journal.Error_Len) :=
              Rejection (Rejection'First .. Rejection'First + Journal.Error_Len - 1);
         end if;
      end;
   end Read_Admitted;
end HRA_N.Application.Legacy_Report_Evidence;
