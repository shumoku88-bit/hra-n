-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Core
--
--  Root of the verified computational kernel (SPARK_Mode => On).
--  Contains zero I/O, zero dynamic heap allocation, and zero side effects.
-------------------------------------------------------------------------------

package HRA_N.Core with
  SPARK_Mode => On
is
   pragma Pure;
end HRA_N.Core;
