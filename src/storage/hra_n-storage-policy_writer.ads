-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Policy_Writer
--
--  Encoders for canonical policy.hra facts.
-------------------------------------------------------------------------------

with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Validity;        use HRA_N.Core.Validity;

package HRA_N.Storage.Policy_Writer is

   function Role_Name (R : Accounting_Role) return String;

   function Encode_Role
     (Id             : String;
      Effective_From : Date_Type;
      Locus          : String;
      Role           : Accounting_Role;
      Replaces_Id    : String := "") return String;

   function Encode_Window
     (Id         : String;
      Start_Date : Date_Type;
      End_Date   : Date_Type;
      Name       : String := "") return String;

end HRA_N.Storage.Policy_Writer;
