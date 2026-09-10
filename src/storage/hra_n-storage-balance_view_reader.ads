-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Balance_View_Reader
--
--  Parses replaceable balance-view configuration (config/balance-view.tsv).
--  Selects neutral Locus x Measure coordinates for current balance views.
-------------------------------------------------------------------------------

with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;

package HRA_N.Storage.Balance_View_Reader is

   Max_Balance_Coordinates : constant := 64;

   type Balance_Coordinate_Array is array (1 .. Max_Balance_Coordinates) of Coordinate_Type;

   type Balance_Coordinate_List is record
      Count  : Natural := 0;
      Values : Balance_Coordinate_Array := [others => Empty_Coordinate];
   end record;

   type Read_Balance_View_Result is record
      Success      : Boolean := False;
      Coordinates  : Balance_Coordinate_List;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Read and normalize balance-view configuration.
   --  If path does not exist, returns Success => True with empty list (Count = 0).
   --  Duplicate coordinates are deduplicated keeping initial presentation order.
   function Read_Balance_View_File (Path : String) return Read_Balance_View_Result;

end HRA_N.Storage.Balance_View_Reader;
