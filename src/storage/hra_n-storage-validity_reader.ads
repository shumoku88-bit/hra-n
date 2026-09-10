-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Validity_Reader
--
--  Parses LOAM-ACTUAL-VALIDITY-HISTORY v2 files into SPARK-verified
--  Validity_Memory instances.
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Storage.Validity_Reader is

   type Read_Validity_Result is record
      Success      : Boolean := False;
      Memory       : Validity_Memory;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Parse an ActualValidity object file.
   function Read_Validity_File (Path : String) return Read_Validity_Result;

   --  Parse and validate an ISO 8601 YYYY-MM-DD string into a verified Date_Type.
   function Parse_Iso_Date
     (Text : String;
      Date : out Date_Type) return Boolean;

end HRA_N.Storage.Validity_Reader;
