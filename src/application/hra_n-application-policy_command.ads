-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Policy_Command
--
--  Proposal-first admission boundary for Accounting Role and Window policies.
--  Appends policy facts to canonical policy.hra under strict snapshot-bound
--  generation transactions.
-------------------------------------------------------------------------------

private with Ada.Strings.Unbounded;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Accounting_Role;      use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;

package HRA_N.Application.Policy_Command is

   type Mutation_Kind is (Mutation_Role, Mutation_Window);

   type Role_Intent is record
      Id             : Token_Text := (Length => 0, Value => [others => ' ']);
      Locus          : Locus_Id;
      Role           : Accounting_Role;
      Effective_From : Date_Type;
      Has_Replaces   : Boolean := False;
      Replaces_Id    : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   type Window_Intent is record
      Id         : Token_Text := (Length => 0, Value => [others => ' ']);
      Start_Date : Date_Type;
      End_Date   : Date_Type;
      Name       : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   type Policy_Proposal is private;

   type Proposal_Result is record
      Success   : Boolean := False;
      Proposal  : Policy_Proposal;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   type Policy_Receipt is record
      Success        : Boolean := False;
      Kind           : Mutation_Kind := Mutation_Role;
      Allocated_Id   : String (1 .. 64) := [others => ' '];
      Allocated_Len  : Natural := 0;
      Snapshot_Id    : String (1 .. 64) := [others => ' '];
      Snapshot_Len   : Natural := 0;
      Error          : String (1 .. 160) := [others => ' '];
      Error_Len      : Natural := 0;
   end record;

   function Propose_Role
     (Paths  : Path_Config;
      Intent : Role_Intent) return Proposal_Result;

   function Propose_Window
     (Paths  : Path_Config;
      Intent : Window_Intent) return Proposal_Result;

   function Commit (Proposal : Policy_Proposal) return Policy_Receipt;

private

   type Policy_Proposal is record
      Valid        : Boolean := False;
      Kind         : Mutation_Kind := Mutation_Role;
      Base_Dir     : String (1 .. Max_Path_Length) := [others => ' '];
      Base_Len     : Natural := 0;
      Expected_Id  : String (1 .. 64) := [others => ' '];
      Expected_Len : Natural := 0;
      Alloc_Id     : String (1 .. 64) := [others => ' '];
      Alloc_Len    : Natural := 0;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end HRA_N.Application.Policy_Command;
