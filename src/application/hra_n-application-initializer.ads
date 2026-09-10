-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Initializer
--
--  Zero-origin household authority initialization.
--  Safely provisions a fresh, mathematically sound Loam v2 authority environment
--  complete with initial LocusAdmission vocabulary, empty event and relation
--  memories, zero-origin coverage evidence, and CURRENT cryptographic manifest.
-------------------------------------------------------------------------------

package HRA_N.Application.Initializer is

   type Init_Result is record
      Success      : Boolean           := False;
      Target_Dir   : String (1 .. 256) := [others => ' '];
      Dir_Len      : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   --  Initialize a brand-new, mathematically sound household directory.
   --  Refuses to overwrite if an existing CURRENT manifest is detected (Fail-Closed).
   function Initialize_Household
     (Base_Dir        : String;
      Custom_Loci_Csv : String := "") return Init_Result;

end HRA_N.Application.Initializer;
