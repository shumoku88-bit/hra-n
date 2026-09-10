-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Catalog_Reader
--
--  Parses tab-separated catalog files (config/locus-catalog.tsv,
--  config/purpose-catalog.tsv, or any identically shaped household catalog)
--  into verified presentation metadata.
--
--  Row grammar:
--    Id HT Display_Name [ HT Description ]
--  The description column is optional; a missing column reads as empty.
--  Blank lines are ignored. Duplicate identities are rejected fail-closed.
-------------------------------------------------------------------------------

with HRA_N.Core.Catalog; use HRA_N.Core.Catalog;

package HRA_N.Storage.Catalog_Reader is

   type Read_Result is record
      Success      : Boolean           := False;
      Catalog      : Catalog_Memory;
      Error_Line   : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   function Read_Catalog_File (Path : String) return Read_Result;

end HRA_N.Storage.Catalog_Reader;
