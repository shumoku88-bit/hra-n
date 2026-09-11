-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Capacity_CLI
--
--  Scriptable capacity authority operations over the shared Application
--  Intent/Query boundary: all-time entitlement readout plus transfer and
--  rebalance proposals committed through the generation transaction.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.UI.Capacity_CLI is

   --  Shared endpoint parsing: the `unallocated` boundary or a purpose.
   --  Reused by the keyboard TUI editors so both surfaces admit one shape.
   function Parse_Coord (Text : String; Coord : out Capacity_Coordinate) return Boolean;

   --  Shared signed-quanta parsing bounded by the admitted quantity range.
   function Parse_Amount (Text : String; Value : out Quanta_Type) return Boolean;

   procedure Dispatch
     (Paths       : Path_Config;
      Command_Idx : Positive;
      Rem_Args    : Natural;
      Success     : out Boolean);

end HRA_N.UI.Capacity_CLI;
