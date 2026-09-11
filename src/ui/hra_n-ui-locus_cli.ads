-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Locus_CLI
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.Locus_CLI is

   procedure Dispatch (Paths : Path_Config; Start_Arg : Positive);

end HRA_N.UI.Locus_CLI;
