-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Split_CLI
--
--  Scriptable split-movement recording over the shared intent boundary:
--  one command carrying signed changes at explicit coordinates. Change
--  text mirrors the journal flow grammar (locus:amount[:measure]); the
--  journal tokenizer rules are the authority and this parser cites them.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Split_CLI is

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

end HRA_N.UI.Split_CLI;
