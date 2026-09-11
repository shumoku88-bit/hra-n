-------------------------------------------------------------------------------
--  HRA-N: shared Scheduled record query implementation
-------------------------------------------------------------------------------

with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Storage.Scheduled_Journal_Reader; use HRA_N.Storage.Scheduled_Journal_Reader;

package body HRA_N.Application.Scheduled_Query is

   procedure Determine_Status
     (Lifecycle    : Scheduled_Lifecycle;
      Id           : Scheduled_Id;
      Status       : out Scheduled_Status_Kind;
      Terminal_Ref : out Token_Text)
   is
   begin
      Status := Status_Open;
      Terminal_Ref := (Length => 0, Value => [others => ' ']);

      --  1. Check completion
      for I in 1 .. Lifecycle.Comp_Count loop
         if Equal_Token (Lifecycle.Comp_Items (I).Scheduled.Token, Id.Token) then
            Status := Status_Completed;
            Terminal_Ref := Lifecycle.Comp_Items (I).Actual.Token;
            return;
         end if;
      end loop;

      --  2. Check replacement
      for I in 1 .. Lifecycle.Repl_Count loop
         if Equal_Token (Lifecycle.Repl_Items (I).Original.Token, Id.Token) then
            Status := Status_Replaced;
            Terminal_Ref := Lifecycle.Repl_Items (I).Replaced_By.Token;
            return;
         end if;
      end loop;

      --  3. Check retirement
      for I in 1 .. Lifecycle.Ret_Count loop
         if Equal_Token (Lifecycle.Ret_Items (I).Scheduled.Token, Id.Token) then
            Status := Status_Retired;
            return;
         end if;
      end loop;
   end Determine_Status;

   procedure Format_Flow_Summary
     (Occ         : Scheduled_Occurrence;
      Summary     : out Flow_Summary_String;
      Summary_Len : out Natural)
   is
      From_Str : String (1 .. 64) := [others => ' '];
      From_Len : Natural := 0;
      To_Str   : String (1 .. 64) := [others => ' '];
      To_Len   : Natural := 0;
      Amount   : Quanta_Type := 0;
   begin
      Summary := [others => ' '];
      Summary_Len := 0;

      for I in 1 .. Occ.Changes.Count loop
         declare
            Chg : constant Scheduled_Change := Occ.Changes.Values (I);
            Tok : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
         begin
            if Chg.Amount < 0 then
               From_Len := Natural'Min (Tok'Length, From_Str'Length);
               From_Str (1 .. From_Len) := Tok (Tok'First .. Tok'First + From_Len - 1);
               Amount := -Chg.Amount;
            elsif Chg.Amount > 0 then
               To_Len := Natural'Min (Tok'Length, To_Str'Length);
               To_Str (1 .. To_Len) := Tok (Tok'First .. Tok'First + To_Len - 1);
            end if;
         end;
      end loop;

      if From_Len > 0 and then To_Len > 0 and then Amount > 0 then
         declare
            Amt_Str  : constant String := Trim (Quanta_Type'Image (Amount), Ada.Strings.Both);
            Meas_Str : constant String := Occ.Measure.Token.Value (1 .. Occ.Measure.Token.Length);
            Full_Str : constant String :=
              From_Str (1 .. From_Len) & " (-" & Amt_Str & " " & Meas_Str & ") -> " &
              To_Str (1 .. To_Len) & " (+" & Amt_Str & " " & Meas_Str & ")";
            L : constant Natural := Natural'Min (Full_Str'Length, Summary'Length);
         begin
            Summary (1 .. L) := Full_Str (Full_Str'First .. Full_Str'First + L - 1);
            Summary_Len := L;
         end;
      else
         if Occ.Changes.Count = 0 then
            Summary (1 .. 10) := "no changes";
            Summary_Len := 10;
         else
            declare
               Chg      : constant Scheduled_Change := Occ.Changes.Values (1);
               Tok      : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
               Amt_Str  : constant String := Trim (Quanta_Type'Image (Chg.Amount), Ada.Strings.Both);
               Full_Str : constant String := Tok & ": " & Amt_Str;
               L        : constant Natural := Natural'Min (Full_Str'Length, Summary'Length);
            begin
               Summary (1 .. L) := Full_Str (Full_Str'First .. Full_Str'First + L - 1);
               Summary_Len := L;
            end;
         end if;
      end if;
   end Format_Flow_Summary;

   function Execute
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Request : Query) return Scheduled_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;

      Result : Scheduled_View :=
        (Status                  => Query_Rejected,
         Snapshot                => (Kind => Snapshot_Unversioned),
         Scope                   => Request.Scope,
         Selected_Day            => Request.Selected_Day,
         Total_Count             => 0,
         Open_Count              => 0,
         Selected_Day_Open_Count => 0,
         Row_Count               => 0,
         Rows                    => [others => Empty_Scheduled_Row],
         Diagnostic              => [others => ' '],
         Diagnostic_Len          => 0);

      Sched_Res : constant Scheduled_Journal_Result :=
        Read_Scheduled_Journal_File (Scheduled_Path_Str (Paths));

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         Result.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;

      function Comes_Before (Left, Right : Scheduled_Row) return Boolean is
      begin
         if Request.Ordering = Order_Due_Ascending then
            if not Equal_Date (Left.Expected_Day, Right.Expected_Day) then
               return Date_Less (Left.Expected_Day, Right.Expected_Day);
            else
               return Left.Source_Order < Right.Source_Order;
            end if;
         else
            return Left.Source_Order < Right.Source_Order;
         end if;
      end Comes_Before;

   begin
      if not Paths.Resolution_Ok then
         Set_Diagnostic (Paths.Error_Reason (1 .. Paths.Error_Len));
         return Result;
      elsif Paths.Is_Versioned then
         Result.Snapshot :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      if not Sched_Res.Success then
         Set_Diagnostic
           ("scheduled.hra: " &
            Sched_Res.Error_Reason (1 .. Sched_Res.Error_Len));
         return Result;
      end if;

      Result.Total_Count := Sched_Res.Lifecycle.Sched_Count;

      for Index in 1 .. Sched_Res.Lifecycle.Sched_Count loop
         declare
            Occ         : constant Scheduled_Occurrence :=
              Sched_Res.Lifecycle.Sched_Items (Index);
            Status      : Scheduled_Status_Kind;
            Term_Ref    : Token_Text;
            Flow_Summ   : Flow_Summary_String;
            Flow_Len    : Natural;
            Include_Row : Boolean;
            Is_Open     : Boolean;
         begin
            Determine_Status (Sched_Res.Lifecycle, Occ.Id, Status, Term_Ref);
            Is_Open := (Status = Status_Open);

            if Is_Open then
               Result.Open_Count := Result.Open_Count + 1;
               if Equal_Date (Occ.Expected_Day, Request.Selected_Day) then
                  Result.Selected_Day_Open_Count :=
                    Result.Selected_Day_Open_Count + 1;
               end if;
            end if;

            Include_Row :=
              (case Request.Scope is
                 when Scope_Current_Open => Is_Open,
                 when Scope_Selected_Day =>
                   Equal_Date (Occ.Expected_Day, Request.Selected_Day),
                 when Scope_All          => True);

            if Include_Row then
               if Result.Row_Count < Max_Scheduled_Rows then
                  Format_Flow_Summary (Occ, Flow_Summ, Flow_Len);
                  Result.Row_Count := Result.Row_Count + 1;
                  Result.Rows (Result.Row_Count) :=
                    (Id           => Occ.Id.Token,
                     Expected_Day => Occ.Expected_Day,
                     Measure      => Occ.Measure.Token,
                     Status       => Status,
                     Terminal_Ref => Term_Ref,
                     Flow_Summary => Flow_Summ,
                     Flow_Len     => Flow_Len,
                     Change_Count => Occ.Changes.Count,
                     Source_Order => Index);
               end if;
            end if;
         end;
      end loop;

      if Result.Row_Count > 1 then
         for Index in 2 .. Result.Row_Count loop
            declare
               Key : constant Scheduled_Row := Result.Rows (Index);
               Pos : Natural := Index - 1;
            begin
               while Pos > 0 and then Comes_Before (Key, Result.Rows (Pos)) loop
                  Result.Rows (Pos + 1) := Result.Rows (Pos);
                  Pos := Pos - 1;
               end loop;
               Result.Rows (Pos + 1) := Key;
            end;
         end loop;
      end if;

      Result.Status := Query_Complete;
      return Result;
   end Execute;

end HRA_N.Application.Scheduled_Query;
