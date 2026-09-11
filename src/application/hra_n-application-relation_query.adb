-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Relation_Query
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;

package body HRA_N.Application.Relation_Query is

   function Endpoint_Label (Endpoint : Relation_Endpoint) return String is
     (if Endpoint.Kind = Endpoint_Household then "household"
      else Endpoint.Name.Value (1 .. Endpoint.Name.Length));

   function Event_Is_Effective
     (Journal   : Journal_Result;
      Target_Id : Token_Text) return Boolean
   is
      Successor : HRA_N.Core.Types.Event_Id;
      Found     : Boolean;
   begin
      for Item of Journal.Events loop
         if Equal_Token (Id (Item).Token, Target_Id) then
            Find_Successor
              (Journal.Metadata, Id (Item), Successor, Found);
            return not Found;
         end if;
      end loop;
      return False;
   end Event_Is_Effective;

   function Claim_Remaining
     (Journal  : Journal_Result;
      Claim_Id : Token_Text) return Long_Long_Integer
   is
      Total : Long_Long_Integer := 0;
   begin
      for D in 1 .. Journal.Relations.Discharge_Count loop
         pragma Loop_Invariant
           (Total >= Long_Long_Integer (D - 1) * Long_Long_Integer (Quanta_Type'First)
            and then Total <= Long_Long_Integer (D - 1) * Long_Long_Integer (Quanta_Type'Last));
         if Equal_Token (Journal.Relations.Discharges (D).Target, Claim_Id)
           and then Event_Is_Effective
             (Journal, Journal.Relations.Discharges (D).Settlement.Token)
         then
            Total := Total
              + Long_Long_Integer (Journal.Relations.Discharges (D).Amount);
         end if;
      end loop;
      return Total;
   end Claim_Remaining;

   function Execute
     (Paths     : Path_Config;
      Open_Only : Boolean := True) return Relation_View
   is
      use HRA_N.Application.Frontend_Types;

      View    : Relation_View;
      Journal : Journal_Result;

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, View.Diagnostic'Length);
      begin
         View.Diagnostic_Len := Len;
         View.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;
   begin
      if not Paths.Resolution_Ok then
         Set_Diagnostic (Paths.Error_Reason (1 .. Paths.Error_Len));
         return View;
      elsif Paths.Is_Versioned then
         View.Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      if not Journal.Success then
         Set_Diagnostic
           ("journal.hra: " &
            Journal.Error_Reason (1 .. Journal.Error_Len));
         return View;
      end if;

      for I in 1 .. Journal.Relations.Claim_Count loop
         exit when View.Count >= Max_Query_Rows;
         declare
            Claim : constant Relation_Claim :=
              Journal.Relations.Claims (I);
            Discharged : constant Long_Long_Integer :=
              Claim_Remaining (Journal, Claim.Id);
            Left : constant Long_Long_Integer :=
              Long_Long_Integer (Claim.Face) - Discharged;
            Source_Ok : constant Boolean :=
              Event_Is_Effective (Journal, Claim.Source.Token);
         begin
            if (not Open_Only or else (Left > 0 and then Source_Ok))
              and then Left >= Long_Long_Integer (Quanta_Type'First)
              and then Left <= Long_Long_Integer (Quanta_Type'Last)
            then
               View.Count := View.Count + 1;
               View.Rows (View.Count) :=
                 (Id        => Claim.Id,
                  Source    => Claim.Source.Token,
                  Debtor    => Claim.Debtor,
                  Creditor  => Claim.Creditor,
                  Measure   => Claim.Measure,
                  Face      => Claim.Face,
                  Remaining => Quanta_Type (Left));
            end if;
         end;
      end loop;

      View.Success := True;
      View.Status := Query_Complete;
      return View;
   end Execute;

   function Links_For_Event
     (Paths    : Path_Config;
      Event_Id : Token_Text) return Event_Links
   is
      Links   : Event_Links;
      Journal : Journal_Result;
   begin
      if not Paths.Resolution_Ok then
         return Links;
      end if;
      Journal := Read_Journal_File (Journal_Path_Str (Paths));
      if not Journal.Success then
         return Links;
      end if;

      for I in 1 .. Journal.Relations.Claim_Count loop
         if Equal_Token (Journal.Relations.Claims (I).Source.Token, Event_Id)
           and then Event_Is_Effective
             (Journal, Journal.Relations.Claims (I).Source.Token)
         then
            Links.Claim_Total := Links.Claim_Total + 1;
            if Links.Claim_Shown < Max_Linked_Rows then
               declare
                  Left : constant Long_Long_Integer :=
                    Long_Long_Integer (Journal.Relations.Claims (I).Face)
                    - Claim_Remaining (Journal, Journal.Relations.Claims (I).Id);
               begin
                  Links.Claim_Shown := Links.Claim_Shown + 1;
                  Links.Claims (Links.Claim_Shown) :=
                    (Id        => Journal.Relations.Claims (I).Id,
                     Debtor    => Journal.Relations.Claims (I).Debtor,
                     Creditor  => Journal.Relations.Claims (I).Creditor,
                     Measure   => Journal.Relations.Claims (I).Measure,
                     Remaining =>
                       (if Left >= Long_Long_Integer (Quanta_Type'First)
                          and then Left <= Long_Long_Integer (Quanta_Type'Last)
                        then Quanta_Type (Left) else Zero_Quanta));
               end;
            end if;
         end if;
      end loop;

      for D in 1 .. Journal.Relations.Discharge_Count loop
         if Equal_Token
           (Journal.Relations.Discharges (D).Settlement.Token, Event_Id)
           and then Event_Is_Effective
             (Journal, Journal.Relations.Discharges (D).Settlement.Token)
         then
            Links.Discharge_Total := Links.Discharge_Total + 1;
            if Links.Discharge_Shown < Max_Linked_Rows then
               Links.Discharge_Shown := Links.Discharge_Shown + 1;
               Links.Discharges (Links.Discharge_Shown) :=
                 (Claim  => Journal.Relations.Discharges (D).Target,
                  Amount => Journal.Relations.Discharges (D).Amount);
            end if;
         end if;
      end loop;

      Links.Success := True;
      return Links;
   end Links_For_Event;

end HRA_N.Application.Relation_Query;
