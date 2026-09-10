with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;

package HRA_N.Application.Authority_Transaction is
   type Family_Update is record
      Changed : Boolean := False;
      Content : Unbounded_String := Null_Unbounded_String;
   end record;
   type Update_Set is array (Manifest_Family) of Family_Update;

   --  Caller must hold CURRENT writer ownership. Expected_Current is the exact
   --  byte snapshot used for domain admission; a changed CURRENT fails closed.
   function Commit
     (Authority_Dir   : String;
      Expected        : Manifest_Record;
      Expected_Current: String;
      Updates         : Update_Set;
      Error_Msg       : out String;
      Error_Len       : out Natural) return Boolean;
end HRA_N.Application.Authority_Transaction;
