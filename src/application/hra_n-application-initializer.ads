-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Initializer
--
--  Creates an initial journal.hra, policy.hra, and scheduled.hra without
--  overwriting an existing household authority.
-------------------------------------------------------------------------------

package HRA_N.Application.Initializer is

   type Init_Result is record
      Success      : Boolean           := False;
      Target_Dir   : String (1 .. 256) := [others => ' '];
      Dir_Len      : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   --  Initialize a new household directory. Refuses to overwrite an existing
   --  journal or policy file.
   function Initialize_Household (Base_Dir : String) return Init_Result;

end HRA_N.Application.Initializer;
