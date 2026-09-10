-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Description_Reader
--
--  Parses LOAM-EVENT-DESCRIPTION-MEMORY v1 files into SPARK-verified
--  Description_Memory instances.
-------------------------------------------------------------------------------

with HRA_N.Core.Description; use HRA_N.Core.Description;

package HRA_N.Storage.Description_Reader is

   type Read_Description_Result is record
      Success      : Boolean := False;
      Memory       : Description_Memory;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Parse an EventDescription object file.
   function Read_Description_File (Path : String) return Read_Description_Result;

   --  Unescape wire text according to LOAM-EVENT-DESCRIPTION-MEMORY v1 rules.
   function Unescape_Text
     (Raw     : String;
      Decoded : out Description_Text) return Boolean;

end HRA_N.Storage.Description_Reader;
