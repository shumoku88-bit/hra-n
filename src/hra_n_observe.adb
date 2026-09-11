------------------------------------------------------------------------------
--  HRA-N: Household Observation v1 machine-readable adapter
--
--  This executable is a read-only frontend over existing Application queries.
--  It does not parse canonical storage, perform accounting arithmetic, or own
--  household authority. The explicit budget interval keeps cross-implementation
--  comparisons on the same query coordinate.
------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Application.Balance_Query;
with HRA_N.Application.Budget_Query;
with HRA_N.Application.Budget_Window;
with HRA_N.Application.Capacity_Query;
with HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

procedure HRA_N_Observe is

   function Token_Str (Token : Token_Text) return String is
   begin
      if Token.Length = 0 then
         return "";
      end if;
      return Token.Value (1 .. Token.Length);
   end Token_Str;

   function Integer_Str (Value : Long_Long_Integer) return String is
   begin
      return Trim (Long_Long_Integer'Image (Value), Both);
   end Integer_Str;

   function Natural_Str (Value : Natural) return String is
   begin
      return Trim (Natural'Image (Value), Both);
   end Natural_Str;

   function Boolean_Str (Value : Boolean) return String is
     (if Value then "true" else "false");

   procedure Meta (Name, Value : String) is
   begin
      Put_Line ("HOBS1" & ASCII.HT & "meta" & ASCII.HT & Name & ASCII.HT & Value);
   end Meta;

   procedure Scalar
     (Namespace, Name, Unit_Name, Value : String)
   is
   begin
      Put_Line
        ("HOBS1" & ASCII.HT & "scalar" & ASCII.HT & Namespace & ASCII.HT &
         Name & ASCII.HT & Unit_Name & ASCII.HT & Value);
   end Scalar;

   procedure Fail (Message : String) is
   begin
      Put_Line (Standard_Error, "hra-n-observe: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Fail;

begin
   if Ada.Command_Line.Argument_Count /= 3 then
      Put_Line
        (Standard_Error,
         "Usage: hra-n-observe DATA_ROOT START END");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Data_Root  : constant String := Ada.Command_Line.Argument (1);
      Start_Text : constant String := Ada.Command_Line.Argument (2);
      End_Text   : constant String := Ada.Command_Line.Argument (3);
      Start_Date : Date_Type;
      End_Date   : Date_Type;
   begin
      if not Parse_Iso_Date (Start_Text, Start_Date)
        or else not Parse_Iso_Date (End_Text, End_Date)
        or else not Date_Less (Start_Date, End_Date)
      then
         Fail ("START and END must be real YYYY-MM-DD dates with START < END");
         return;
      end if;

      declare
         Paths    : constant Path_Config := Resolve_Paths (Data_Root);
         Balances : constant HRA_N.Application.Balance_Query.Balance_View :=
           HRA_N.Application.Balance_Query.Execute (Paths);
         Budget   : constant HRA_N.Application.Budget_Query.Budget_View :=
           HRA_N.Application.Budget_Query.Execute_Window
             (Paths      => Paths,
              Start_Date => Start_Date,
              End_Date   => End_Date);
         Capacity : constant HRA_N.Application.Capacity_Query.Capacity_View :=
           HRA_N.Application.Capacity_Query.Execute (Paths);
      begin
         if Balances.Status /= HRA_N.Application.Frontend_Types.Query_Complete then
            if Balances.Diagnostic_Len > 0 then
               Fail
                 (Balances.Diagnostic (1 .. Balances.Diagnostic_Len));
            else
               Fail ("balance query rejected");
            end if;
            return;
         elsif Budget.Status /= HRA_N.Application.Frontend_Types.Query_Complete then
            if Budget.Diagnostic_Len > 0 then
               Fail (Budget.Diagnostic (1 .. Budget.Diagnostic_Len));
            else
               Fail ("budget query rejected");
            end if;
            return;
         elsif not Capacity.Success then
            if Capacity.Error_Len > 0 then
               Fail (Capacity.Error (1 .. Capacity.Error_Len));
            else
               Fail ("capacity query rejected");
            end if;
            return;
         end if;

         --  No stdout is emitted before all three queries have succeeded.
         Meta ("schema", "1");
         Meta ("implementation", "hra-n");
         if Paths.Is_Versioned then
            Meta ("snapshot_kind", "versioned");
            Meta ("snapshot_id", Snapshot_Id_Str (Paths));
         else
            Meta ("snapshot_kind", "unversioned");
         end if;
         Meta ("window_start", Format_Iso_Date (Start_Date));
         Meta ("window_end_exclusive", Format_Iso_Date (End_Date));
         Meta ("balance_scope", "all");
         Meta ("capacity_scope", "all-coordinates");

         for I in 1 .. Balances.Row_Count loop
            declare
               Row : constant HRA_N.Application.Balance_Query.Balance_Row :=
                 Balances.Rows (I);
               Origin : constant String :=
                 (case Row.Epistemic_Status is
                    when HRA_N.Application.Balance_Query.Status_Known_Zero =>
                      "known-zero-origin",
                    when HRA_N.Application.Balance_Query.Status_Unknown_Origin =>
                      "unknown-origin",
                    when HRA_N.Application.Balance_Query.Status_Conflict =>
                      "conflict");
            begin
               Put_Line
                 ("HOBS1" & ASCII.HT & "balance" & ASCII.HT &
                  Token_Str (Row.Locus) & ASCII.HT & Token_Str (Row.Measure) &
                  ASCII.HT & Integer_Str (Row.Amount) & ASCII.HT & Origin &
                  ASCII.HT & Natural_Str (Row.Posting_Count));
            end;
         end loop;

         for I in 1 .. Budget.Report.Row_Count loop
            declare
               Row : constant HRA_N.Application.Budget_Window.Envelope_Row :=
                 Budget.Report.Rows (I);
            begin
               Put_Line
                 ("HOBS1" & ASCII.HT & "budget" & ASCII.HT &
                  Token_Str (Row.Purpose) & ASCII.HT & "jpy" & ASCII.HT &
                  Integer_Str (Long_Long_Integer (Row.Entitlement)) & ASCII.HT &
                  Integer_Str (Long_Long_Integer (Row.Consumption)) & ASCII.HT &
                  Integer_Str (Long_Long_Integer (Row.Remaining)));
            end;
         end loop;

         Scalar
           ("budget", "total_entitlement", "jpy",
            Integer_Str (Long_Long_Integer (Budget.Report.Total_Entitlement)));
         Scalar
           ("budget", "total_consumption", "jpy",
            Integer_Str (Long_Long_Integer (Budget.Report.Total_Consumption)));
         Scalar
           ("budget", "total_remaining", "jpy",
            Integer_Str (Long_Long_Integer (Budget.Report.Total_Remaining)));
         Scalar
           ("budget", "unallocated_funds", "jpy",
            Integer_Str (Long_Long_Integer (Budget.Report.Unallocated_Funds)));
         Scalar
           ("budget", "capacity_sum", "jpy",
            Integer_Str (Budget.Report.Capacity_Sum));
         Scalar
           ("budget", "movements_count", "count",
            Natural_Str (Budget.Report.Movements_Count));
         Scalar
           ("budget", "events_considered", "count",
            Natural_Str (Budget.Report.Events_Considered));
         Scalar
           ("budget", "effective_complete", "bool",
            Boolean_Str (Budget.Report.Effective_Complete));

         for I in 1 .. Capacity.Count loop
            declare
               Row : constant HRA_N.Application.Capacity_Query.Entitlement_Row :=
                 Capacity.Rows (I);
               Kind : constant String :=
                 (if Row.Coord.Kind = Coord_Unallocated then "unallocated"
                  else "purpose");
               Name : constant String :=
                 (if Row.Coord.Kind = Coord_Unallocated then "-"
                  else Token_Str (Row.Coord.Purpose));
            begin
               Put_Line
                 ("HOBS1" & ASCII.HT & "capacity" & ASCII.HT & Kind &
                  ASCII.HT & Name & ASCII.HT & "jpy" & ASCII.HT &
                  Integer_Str (Long_Long_Integer (Row.Amount)));
            end;
         end loop;
         Scalar
           ("capacity", "effective_complete", "bool",
            Boolean_Str (Capacity.Complete));

         Meta ("status", "complete");
      end;
   end;
end HRA_N_Observe;
