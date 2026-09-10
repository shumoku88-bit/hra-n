-------------------------------------------------------------------------------
--  HRA-N: shared frontend result types
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Application.Frontend_Types with
  SPARK_Mode => On
is
   pragma Pure;

   type Query_Status is
     (Query_Complete,
      Query_Partial,
      Query_Rejected);

   type Snapshot_Kind is
     (Snapshot_Unversioned,
      Snapshot_Versioned);

   type Snapshot_Reference (Kind : Snapshot_Kind := Snapshot_Unversioned) is record
      case Kind is
         when Snapshot_Unversioned =>
            null;
         when Snapshot_Versioned =>
            Identity : Token_Text;
      end case;
   end record;

   Max_Diagnostic_Length : constant := 160;

   subtype Diagnostic_Length is Natural range 0 .. Max_Diagnostic_Length;
   subtype Diagnostic_Text is String (1 .. Max_Diagnostic_Length);

end HRA_N.Application.Frontend_Types;
