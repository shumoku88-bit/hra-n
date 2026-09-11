-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Policy_Command
--
--  Proposal-first admission boundary for Accounting Role, Window, and Actual
--  Routing policy facts. Appends to canonical policy.hra under strict
--  snapshot-bound generation transactions.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Application.Proposal;
with HRA_N.Core.Accounting_Role;      use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Actual_Routing;       use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;

package HRA_N.Application.Policy_Command is

   type Locus_Intent is record
      Locus : Locus_Id;
   end record;

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

   type Routing_Intent is record
      Locus          : Locus_Id;
      Effective_Kind : Routing_Effective_Kind := Routing_Initial;
      Effective_On   : Date_Type := (Year => 1900, Month => 1, Day => 1);
      Managed        : Boolean := True;
      Purpose        : Token_Text := (Length => 0, Value => [others => ' ']);
   end record;

   --  Shared snapshot-bound proposal vocabulary: the allocated role or
   --  window identity is the primary identity. Callers know their mutation
   --  kind from the intent they proposed, so no kind travels along.
   subtype Policy_Proposal is HRA_N.Application.Proposal.Authority_Proposal;
   subtype Proposal_Result is HRA_N.Application.Proposal.Proposal_Result;
   subtype Policy_Receipt is HRA_N.Application.Proposal.Receipt;

   function Propose_Locus
     (Paths  : Path_Config;
      Intent : Locus_Intent) return Proposal_Result;

   function Propose_Role
     (Paths  : Path_Config;
      Intent : Role_Intent) return Proposal_Result;

   function Propose_Window
     (Paths  : Path_Config;
      Intent : Window_Intent) return Proposal_Result;

   function Propose_Routing
     (Paths  : Path_Config;
      Intent : Routing_Intent) return Proposal_Result;

   function Commit (Proposal : Policy_Proposal) return Policy_Receipt
     renames HRA_N.Application.Proposal.Commit;



end HRA_N.Application.Policy_Command;
