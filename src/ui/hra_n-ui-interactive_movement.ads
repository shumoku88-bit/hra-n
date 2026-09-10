-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Interactive_Movement
--
--  Interactive CLI entrance for verified Movement recording.
--  Guides the human operator through occurrence date, locus admission,
--  exact amount, and human-facing description with admission preview
--  and explicit confirmation before committing to authority.
-------------------------------------------------------------------------------

package HRA_N.UI.Interactive_Movement is

   --  Run the interactive terminal entrance.
   --  Returns Success = True if a movement was confirmed and committed.
   procedure Run_Interactive
     (Authority_Dir : String;
      Success       : out Boolean);

end HRA_N.UI.Interactive_Movement;
