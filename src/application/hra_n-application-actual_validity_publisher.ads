-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Actual_Validity_Publisher
--
--  Occurrence-date attachment and correction publisher.
--  Adheres strictly to the normative authority protocol:
--    1. CURRENT writer ownership
--    2. Re-reads Movement, Correction, and Validity authorities under lock
--    3. Requires target to be current correction frontier tip
--    4. If target date matches, reports exact no-op without writing CURRENT
--    5. If target date differs, appends revision fact + correction relation
--    6. If target is undated, appends initial validity fact
--    7. Only ActualValidity manifest family changes; all other 5 families preserved
--    8. Admits complete candidate validity frontier before committing
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Actual_Validity_Publisher is

   type Date_Receipt is record
      Success      : Boolean           := False;
      Target       : Event_Id          := (Token => (Length => 0, Value => [others => ' ']));
      Has_Previous : Boolean           := False;
      Previous     : Date_Type         := (Year => 2026, Month => 1, Day => 1);
      Valid_On     : Date_Type         := (Year => 2026, Month => 1, Day => 1);
      Changed      : Boolean           := False;
      First_Date   : Boolean           := False;
      Error_Reason : String (1 .. 256) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   function Publish_Date
     (Authority_Dir   : String;
      Correction_Path : String;
      Target          : Event_Id;
      Valid_On        : Date_Type) return Date_Receipt;

   function Publish_Date
     (Authority_Dir   : String;
      Correction_Path : String;
      Target_Str      : String;
      Date_Str        : String) return Date_Receipt;

end HRA_N.Application.Actual_Validity_Publisher;
