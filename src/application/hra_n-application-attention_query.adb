-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Attention_Query
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Attention_Query is

   function Due_Label (Due : Attention_Due) return String is
     (case Due.Kind is
         when Due_On_Date    => "due " & Format_Iso_Date (Due.Due_Date),
         when No_Due_Date    => "no due date",
         when Due_Undetermined => "due unknown");

   function Execute (Paths : Path_Config) return Attention_View is
      use HRA_N.Application.Frontend_Types;

      View   : Attention_View;
      Policy : Policy_Result;

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
      elsif Paths.Is_Versioned then
         View.Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      Policy := Read_Policy_File (Policy_Path_Str (Paths));
      if not Policy.Success then
         Set_Diagnostic
           ("policy.hra: " &
            Policy.Error_Reason (1 .. Policy.Error_Len));
         return View;
      end if;

      for I in 1 .. Policy.Attention.Item_Count loop
         exit when View.Count >= Max_Query_Rows;
         if not Has_Closure
           (Policy.Attention, Policy.Attention.Items (I).Id)
         then
            View.Count := View.Count + 1;
            View.Rows (View.Count) :=
              (Id      => Policy.Attention.Items (I).Id,
               Context => Policy.Attention.Items (I).Context,
               Due     => Policy.Attention.Items (I).Due);
         end if;
      end loop;

      View.Success := True;
      View.Status := Query_Complete;
      return View;
   end Execute;

end HRA_N.Application.Attention_Query;
