-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Reader
--
--  Parses LOAM-SCHEDULED-LIFECYCLE v1 files into SPARK-verified
--  Scheduled_Lifecycle instances.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Storage.Scheduled_Reader is

   type Read_Scheduled_Result is record
      Success      : Boolean             := False;
      Lifecycle    : Scheduled_Lifecycle;
      Error_Line   : Natural             := 0;
      Error_Reason : String (1 .. 128)   := [others => ' '];
      Error_Len    : Natural             := 0;
   end record;

   --  Parse a complete LOAM-SCHEDULED-LIFECYCLE v1 file.
   function Read_Scheduled_File (Path : String) return Read_Scheduled_Result;

end HRA_N.Storage.Scheduled_Reader;
