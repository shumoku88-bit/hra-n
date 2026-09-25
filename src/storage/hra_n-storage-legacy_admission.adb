with HRA_N.Core.Accounting_Role; use HRA_N.Core.Accounting_Role;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Window_Policy; use HRA_N.Core.Window_Policy;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader; use HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;

package body HRA_N.Storage.Legacy_Admission is
   function Event_Exists (Journal : Journal_Result; Target : Event_Id) return Boolean is
   begin
      for Item of Journal.Events loop
         if Equal_Token (Id (Item).Token, Target.Token) then
            return True;
         end if;
      end loop;
      return False;
   end Event_Exists;

   function Failure
     (Journal   : Journal_Result;
      Policy    : Policy_Result;
      Scheduled : Scheduled_Journal_Result) return String
   is
      Life : Scheduled_Lifecycle renames Scheduled.Lifecycle;
   begin
      if not Journal.Success then
         return "journal: " & Journal.Error_Reason (1 .. Journal.Error_Len);
      elsif not Policy.Success then
         return "policy: " & Policy.Error_Reason (1 .. Policy.Error_Len);
      elsif not Scheduled.Success then
         return "scheduled journal rejected";
      end if;
      if Natural (Journal.Events.Length) > Max_Validity_Entries then
         return "journal exceeds admitted event capacity";
      elsif not All_Role_Laws_Hold (Policy.Roles) then
         return "role declarations violate policy laws";
      elsif not Windows_Are_Sound (Policy.Windows) then
         return "window declarations violate window laws";
      elsif not Scheduled_Ids_Are_Unique (Life)
        or else not Completions_Reference_Known (Life)
        or else not Retirements_Reference_Known (Life)
        or else not Replacements_Reference_Known (Life)
        or else not Terminal_Evidence_Compatible (Life)
        or else not Replacement_Terminal_Compatible (Life)
        or else not Replacements_Are_One_To_One (Life)
        or else not Terminal_Targets_Are_Unique (Life)
        or else not Replacement_History_Is_Acyclic (Life)
      then
         return "scheduled lifecycle law violated";
      end if;

      for Item of Journal.Events loop
         if not Is_Balanced_Per_Measure (Item) then
            return "journal movement breaks per-measure conservation";
         end if;
      end loop;

      for Index in 1 .. Life.Sched_Count loop
         declare
            Item : constant Scheduled_Occurrence := Life.Sched_Items (Index);
         begin
            if Item.Changes.Count < 2 then
               return "scheduled occurrence needs two changes";
            end if;
            for Change_Index in 1 .. Item.Changes.Count loop
               if Item.Changes.Values (Change_Index).Amount = 0 then
                  return "scheduled change must be non-zero";
               end if;
            end loop;
            if not Is_Conserved (Item) then
               return "scheduled occurrence breaks conservation";
            end if;
            for Other in Index + 1 .. Life.Sched_Count loop
               if Equal_Token (Item.Id.Token, Life.Sched_Items (Other).Id.Token) then
                  return "duplicate scheduled identity";
               end if;
            end loop;
         end;
      end loop;

      for Index in 1 .. Life.Comp_Count loop
         if not Event_Exists (Journal, Life.Comp_Items (Index).Actual) then
            return "scheduled completion references unknown actual";
         end if;
      end loop;
      return "";
   end Failure;
end HRA_N.Storage.Legacy_Admission;
