-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Interactive_Movement
--
--  Interactive CLI entrance for verified Movement recording.
--  Guides the human operator through occurrence date, locus admission,
--  exact amount, and human-facing description with admission preview
--  and explicit confirmation before committing to authority.
--
--  When a locus catalog path is provided and parses successfully, the
--  admitted-locus listing is enriched with curated display names.
--  Absent or malformed catalog evidence degrades honestly to raw
--  identifiers; it never blocks admission.
-------------------------------------------------------------------------------

package HRA_N.UI.Interactive_Movement is

   --  Run the interactive terminal entrance.
   --  Returns Success = True if a movement was confirmed and committed.
   procedure Run_Interactive
     (Authority_Dir : String;
      Catalog_Path  : String := "";
      Success       : out Boolean);

end HRA_N.UI.Interactive_Movement;
