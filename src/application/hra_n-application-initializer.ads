-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Initializer
--
--  Creates the first immutable three-stream generation and atomically selects
--  it without overwriting an existing household authority.
-------------------------------------------------------------------------------

package HRA_N.Application.Initializer is

   type Init_Result is record
      Success      : Boolean           := False;
      Target_Dir   : String (1 .. 256) := [others => ' '];
      Dir_Len      : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   --  Initialize a new household directory. Refuses a selected generation or
   --  legacy root authority; unselected crash residue is retryable.
   function Initialize_Household (Base_Dir : String) return Init_Result;

end HRA_N.Application.Initializer;
