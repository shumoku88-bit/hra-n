------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Canonical_Authority
--
--  Canonical Loam authority discovery across Actual, Scheduled, locus
--  admission, and zero-origin coverage domains.
------------------------------------------------------------------------------

package HRA_N.Application.Canonical_Authority is

   type Authority_State is
     (Legacy_Only,
      Canonical_Present,
      Probe_Failed);

   type Authority_Probe is record
      State          : Authority_State   := Probe_Failed;
      Diagnostic     : String (1 .. 192) := [others => ' '];
      Diagnostic_Len : Natural           := 0;
   end record;

   --  Probe Root_Path for canonical Loam authority markers:
   --  scheduled.loam, actual.loam, locus-admission.loam, or
   --  zero-origin-coverage.loam.
   --
   --  - Canonical_Present: One or more canonical markers exist. Partial presence
   --    deliberately selects the canonical route so downstream components fail
   --    closed rather than silently falling back to the legacy journal.
   --  - Legacy_Only: Inspection completed reliably and no canonical markers exist.
   --  - Probe_Failed: Filesystem inspection could not be completed reliably
   --    (e.g. invalid path, inaccessible directory, filesystem error).
   --    Callers MUST fail closed and MUST NOT fall back to legacy authority.
   function Probe
     (Root_Path : String) return Authority_Probe;

end HRA_N.Application.Canonical_Authority;
