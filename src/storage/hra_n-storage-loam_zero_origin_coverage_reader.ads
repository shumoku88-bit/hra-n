-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader
--
--  Read-only bridge for LOAM-ZERO-ORIGIN-COVERAGE v1.
-------------------------------------------------------------------------------

with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;

package HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader is

   type Read_Result is record
      Success      : Boolean := False;
      Present      : Boolean := False;
      Coverage     : Zero_Origin_Coverage;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 160) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Decode one exact canonical byte image. Duplicate coordinates and any
   --  representation beyond HRA-N's bounded coverage capacity fail closed.
   function Read_Content (Content : String) return Read_Result;

   --  A missing file is successful empty affirmative evidence. An existing
   --  unreadable or malformed file is rejected and never treated as missing.
   function Read_File (Path : String) return Read_Result;

end HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader;
