-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Completion_Publisher
--
--  Canonical relation-first Scheduled completion publisher.
--
--  One ordered ownership interval covers both authorities:
--
--    scheduled.loam -> actual.loam
--
--  The Scheduled -> Actual claim is published first.  If Actual publication
--  does not complete, the retained claim remains inert and a later retry can
--  select the same deterministic endpoint.
-------------------------------------------------------------------------------

with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Scheduled;   use HRA_N.Core.Scheduled;
with HRA_N.Core.Types;       use HRA_N.Core.Types;
with HRA_N.Core.Validity;    use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Scheduled_Completion_Publisher is

   type Completion_Publication_State is
     (Completion_Not_Published,
      Completion_Published_Fresh_Claim,
      Completion_Published_Resumed_Claim,
      Completion_Claim_Inert);

   type Completion_Draft is record
      Scheduled          : Scheduled_Id;
      Has_Execution_Date : Boolean := False;
      Execution_Date     : Date_Type := (Year => 2026, Month => 1, Day => 1);
      Description        : Description_Text;
   end record;

   type Publish_Result is record
      State        : Completion_Publication_State := Completion_Not_Published;
      Actual_Id    : Event_Id;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Publish one Scheduled realization as a canonical Actual Event.
   --
   --  The Actual identity is deterministic:
   --    scheduled-completion:<ScheduledId>
   --
   --  Fresh and resumed interrupted completions both use the retained
   --  Scheduled occurrence as the source of physical Effects.
   function Publish_Completion
     (Root_Path : String;
      Draft     : Completion_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Completion_Publisher;
