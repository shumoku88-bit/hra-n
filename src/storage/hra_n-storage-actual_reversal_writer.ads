-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Actual_Reversal_Writer
--
--  Appends an explicit REVERSE fact to LOAM-ACTUAL-REVERSAL-MEMORY v1 files
--  using atomic file replacement and advisory writer locking.
-------------------------------------------------------------------------------

package HRA_N.Storage.Actual_Reversal_Writer is

   --  Append a reversal record into the target actual-reversals.loam file.
   --  If the file does not exist, it is initialized with the standard v1 header.
   --  Performs preflight checks ensuring target and reversal are valid, distinct,
   --  and not already present.
   function Append_Actual_Reversal
     (File_Path    : String;
      Target_Id    : String;
      Reversal_Id  : String;
      Err_Buf      : out String;
      Err_Len      : out Natural) return Boolean;

end HRA_N.Storage.Actual_Reversal_Writer;
