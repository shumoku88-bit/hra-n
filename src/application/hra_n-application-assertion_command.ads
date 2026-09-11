-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Assertion_Command
--
--  Proposal-first admission boundary for balance assertion evidence.
--  Encodes physical balance observations into canonical journal.hra under
--  strict snapshot-bound generation transactions.
-------------------------------------------------------------------------------

private with Ada.Strings.Unbounded;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Assertion_Command is

   type Assertion_Intent is record
      Id          : Token_Text;
      Valid_On    : Date_Type;
      Locus       : Locus_Id;
      Measure     : Measure_Id;
      Amount      : Quanta_Type := 0;
      Description : Token_Text;
   end record;

   type Assertion_Proposal is private;

   type Proposal_Result is record
      Success   : Boolean := False;
      Proposal  : Assertion_Proposal;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   type Assertion_Receipt is record
      Success          : Boolean := False;
      Assertion_Id     : String (1 .. 64) := [others => ' '];
      Assertion_Id_Len : Natural := 0;
      Snapshot_Id      : String (1 .. 64) := [others => ' '];
      Snapshot_Len     : Natural := 0;
      Error            : String (1 .. 160) := [others => ' '];
      Error_Len        : Natural := 0;
   end record;

   function Propose
     (Paths  : Path_Config;
      Intent : Assertion_Intent) return Proposal_Result;

   function Commit (Proposal : Assertion_Proposal) return Assertion_Receipt;

private

   type Assertion_Proposal is record
      Valid        : Boolean := False;
      Base_Dir     : String (1 .. Max_Path_Length) := [others => ' '];
      Base_Len     : Natural := 0;
      Expected_Id  : String (1 .. 64) := [others => ' '];
      Expected_Len : Natural := 0;
      Assert_Id    : String (1 .. 64) := [others => ' '];
      Assert_Len   : Natural := 0;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end HRA_N.Application.Assertion_Command;
