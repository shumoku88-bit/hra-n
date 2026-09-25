-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Initializer
--
--  Creates a canonical Loam household foundation without overwriting an
--  existing authority. The old generation constructor serves test fixtures.
-------------------------------------------------------------------------------

package HRA_N.Application.Initializer is

   type Init_Result is record
      Success      : Boolean           := False;
      Target_Dir   : String (1 .. 256) := [others => ' '];
      Dir_Len      : Natural           := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   --  Initialize a new canonical Loam household directory. Creates the foundational
   --  Loam files (actual.loam, locus-admission.loam, accounting-role.loam,
   --  zero-origin-coverage.loam, scheduled.loam, capacity.loam, actual-routing.loam).
   --  Refuses to overwrite existing canonical or legacy authorities.
   function Initialize_Household (Base_Dir : String) return Init_Result;

   --  Transitional regression-fixture constructor for the remaining three-stream
   --  tests. Not exposed by the CLI; retire with the dependent legacy paths.
   function Initialize_Legacy_Household (Base_Dir : String) return Init_Result;

end HRA_N.Application.Initializer;
