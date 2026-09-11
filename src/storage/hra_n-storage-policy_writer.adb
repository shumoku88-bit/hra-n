-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Policy_Writer
-------------------------------------------------------------------------------

package body HRA_N.Storage.Policy_Writer is

   function Role_Name (R : Accounting_Role) return String is
   begin
      return (case R is
                when Role_Asset     => "ASSET",
                when Role_Liability => "LIABILITY",
                when Role_Equity    => "EQUITY",
                when Role_Income    => "INCOME",
                when Role_Expense   => "EXPENSE");
   end Role_Name;

   function Encode_Role
     (Id             : String;
      Effective_From : Date_Type;
      Locus          : String;
      Role           : Accounting_Role;
      Replaces_Id    : String := "") return String
   is
      Base : constant String :=
        "ROLE " & Id & " " & Format_Iso_Date (Effective_From) & " " &
        Locus & " " & Role_Name (Role);
   begin
      if Replaces_Id'Length > 0 then
         return Base & " REPLACES " & Replaces_Id & ASCII.LF;
      else
         return Base & ASCII.LF;
      end if;
   end Encode_Role;

   function Encode_Window
     (Id         : String;
      Start_Date : Date_Type;
      End_Date   : Date_Type;
      Name       : String := "") return String
   is
      Base : constant String :=
        "WINDOW " & Id & " " & Format_Iso_Date (Start_Date) & " -> " &
        Format_Iso_Date (End_Date);
   begin
      if Name'Length > 0 then
         return Base & " """ & Name & """" & ASCII.LF;
      else
         return Base & ASCII.LF;
      end if;
   end Encode_Window;

end HRA_N.Storage.Policy_Writer;
