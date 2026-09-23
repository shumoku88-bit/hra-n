------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Canonical_Authority
--
--  Canonical Loam authority discovery across Actual, Scheduled, and
--  locus admission domains.
------------------------------------------------------------------------------

package HRA_N.Application.Canonical_Authority is

   --  True when any canonical Loam authority marker exists in Root_Path:
   --  scheduled.loam, actual.loam, or locus-admission.loam.
   --
   --  OR-composition is deliberate: a partially present canonical authority
   --  must select the canonical route so HRA-N fails closed on incomplete or
   --  malformed state rather than silently falling back to the legacy journal
   --  and creating split authority.
   function Canonical_Authority_Present
     (Root_Path : String) return Boolean;

end HRA_N.Application.Canonical_Authority;
