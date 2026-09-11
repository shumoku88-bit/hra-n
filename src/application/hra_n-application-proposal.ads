-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Proposal
--
--  Shared snapshot-bound proposal and generation-transaction commit used
--  by every Intent/Proposal/Receipt command. One vocabulary, one commit
--  path: per-command packages keep intent validation and fact encoding,
--  and otherwise delegate here instead of copying the machinery.
--
--  A proposal carries exact candidate bytes for all three streams plus
--  the snapshot it was prepared against. Commit re-reads authority under
--  writer ownership and rejects a stale proposal; retrying with the same
--  proposal recovers the same receipt instead of a second generation.
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded;

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.Application.Proposal is

   type Authority_Proposal is private;

   type Proposal_Result is record
      Success   : Boolean := False;
      Proposal  : Authority_Proposal;
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;
   end record;

   type Receipt is record
      Success       : Boolean := False;
      Primary_Id    : String (1 .. 64) := [others => ' '];
      Primary_Len   : Natural := 0;
      Secondary_Id  : String (1 .. 64) := [others => ' '];
      Secondary_Len : Natural := 0;
      Snapshot_Id   : String (1 .. 64) := [others => ' '];
      Snapshot_Len  : Natural := 0;
      Error         : String (1 .. 160) := [others => ' '];
      Error_Len     : Natural := 0;
   end record;

   --  Bind exact candidate bytes to the selected snapshot. Primary names
   --  the newly allocated identity; Secondary names the linked identity
   --  (replaced, reversed, or scheduled target) or stays empty. Identities
   --  longer than 64 characters yield an invalid proposal, which Commit
   --  rejects; identities are never truncated.
   function Seal
     (Paths        : Path_Config;
      Primary_Id   : String;
      Secondary_Id : String;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String)
      return Authority_Proposal;

   --  Commit through the generation transaction with stale rejection and
   --  idempotent retry. An invalid proposal is rejected, never committed.
   function Commit (Proposal : Authority_Proposal) return Receipt;

   function Primary_Id (Proposal : Authority_Proposal) return String;
   function Secondary_Id (Proposal : Authority_Proposal) return String;
   function Expected_Snapshot (Proposal : Authority_Proposal) return String;

   --  Reject a proposal under construction with a diagnostic.
   procedure Fail (Result : in out Proposal_Result; Message : String);

   --  Functional form for single-expression returns.
   function Failed
     (Result  : Proposal_Result;
      Message : String) return Proposal_Result;

   --  Canonical text files end each generation image with a newline; a
   --  candidate that would glue onto an unterminated base is refused.
   function Ends_With_Newline
     (Content : Ada.Strings.Unbounded.Unbounded_String) return Boolean;

private

   type Authority_Proposal is record
      Valid        : Boolean := False;
      Base_Dir     : String (1 .. Max_Path_Length) := [others => ' '];
      Base_Len     : Natural := 0;
      Expected_Id  : String (1 .. Max_Snapshot_Id_Length) := [others => ' '];
      Expected_Len : Natural := 0;
      Primary      : String (1 .. 64) := [others => ' '];
      Primary_Len  : Natural := 0;
      Secondary    : String (1 .. 64) := [others => ' '];
      Secondary_Len : Natural := 0;
      Journal      : Ada.Strings.Unbounded.Unbounded_String;
      Policy       : Ada.Strings.Unbounded.Unbounded_String;
      Scheduled    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end HRA_N.Application.Proposal;
