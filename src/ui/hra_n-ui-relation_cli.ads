-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Relation_CLI
--
--  Scriptable relation operations over the shared Application
--  Intent/Query boundary: open-claim readout plus raise-claim and
--  discharge proposals committed through the generation transaction.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;

package HRA_N.UI.Relation_CLI is

   --  Shared endpoint parsing: `household`, a bare external name, or the
   --  canonical `ext:<name>` wire form. Reused by the keyboard detail
   --  editors so both surfaces admit one shape.
   function Parse_Endpoint
     (Text     : String;
      Endpoint : out Relation_Endpoint) return Boolean;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

end HRA_N.UI.Relation_CLI;
