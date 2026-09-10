-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Text_Fields
--
--  Shared tab-separated field slicing primitives for all Loam-format
--  readers. Rows carrying more fields than Max_Fields saturate the array;
--  callers enforce their exact expected column count and therefore reject
--  saturated rows as malformed.
-------------------------------------------------------------------------------

package HRA_N.Storage.Text_Fields is

   Max_Fields : constant := 12;

   type Field_Slice is record
      First : Positive := 1;
      Last  : Natural  := 0;
   end record;

   type Field_Array is array (1 .. Max_Fields) of Field_Slice;

   --  Split Line on ASCII.HT tab separators into up to Max_Fields slices.
   --  Count reports how many slices were produced (0 for an empty line).
   --  A trailing empty field produced by a final tab is NOT counted here;
   --  readers needing that behavior (see Description_Reader) extend locally.
   procedure Split_Tabs
     (Line   : String;
      Fields : out Field_Array;
      Count  : out Natural);

end HRA_N.Storage.Text_Fields;
