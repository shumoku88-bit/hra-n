-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Journal_Writer
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded;         use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;             use Ada.Strings.Fixed;
with HRA_N.Core.Validity;           use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer;   use HRA_N.Storage.Atomic_Writer;

package body HRA_N.Storage.Scheduled_Journal_Writer is

   function Write_Scheduled_Journal_File
     (Path      : String;
      Lifecycle : Scheduled_Lifecycle) return Write_Result
   is
      Buf       : Unbounded_String;
      Result    : Write_Result;
      Err_Buf   : String (1 .. 128) := [others => ' '];
      Err_Len   : Natural := 0;

      procedure Set_Error (Msg : String) is
         L : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Len := L;
         Result.Error_Reason (1 .. L) := Msg (Msg'First .. Msg'First + L - 1);
      end Set_Error;

   begin
      if Index (Path, "/.hra/generations/") /= 0 then
         Set_Error ("Selected generations are immutable; use an authority transaction");
         return Result;
      end if;

      Append (Buf, "# HRA-N Scheduled Journal" & ASCII.LF);
      Append (Buf, "# Facts: SCHED, COMPLETE, RETIRE, REPLACE" & ASCII.LF & ASCII.LF);

      for I in 1 .. Lifecycle.Sched_Count loop
         declare
            Occ     : constant Scheduled_Occurrence := Lifecycle.Sched_Items (I);
            Id_Str  : constant String := Occ.Id.Token.Value (1 .. Occ.Id.Token.Length);
            Date_Str : constant String := Format_Iso_Date (Occ.Expected_Day);
            Mea_Str : constant String := Occ.Measure.Token.Value (1 .. Occ.Measure.Token.Length);
         begin
            Append (Buf, "SCHED ");
            Append (Buf, Id_Str);
            Append (Buf, " ");
            Append (Buf, Date_Str);

            for C in 1 .. Occ.Changes.Count loop
               declare
                  Chg : constant Scheduled_Change := Occ.Changes.Values (C);
                  Loc : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
                  Amt : constant String := Long_Long_Integer'Image (Long_Long_Integer (Chg.Amount));
                  Amt_Trimmed : constant String :=
                    (if Amt'Length > 0 and then Amt (Amt'First) = ' '
                     then Amt (Amt'First + 1 .. Amt'Last)
                     else Amt);
               begin
                  Append (Buf, " ");
                  Append (Buf, Loc);
                  Append (Buf, ":");
                  Append (Buf, Amt_Trimmed);
                  if Mea_Str /= "jpy" then
                     Append (Buf, ":");
                     Append (Buf, Mea_Str);
                  end if;
               end;
            end loop;

            Append (Buf, ASCII.LF);
         end;
      end loop;

      for I in 1 .. Lifecycle.Comp_Count loop
         Append
           (Buf,
            "COMPLETE " &
            Lifecycle.Comp_Items (I).Scheduled.Token.Value
              (1 .. Lifecycle.Comp_Items (I).Scheduled.Token.Length) & " " &
            Lifecycle.Comp_Items (I).Actual.Token.Value
              (1 .. Lifecycle.Comp_Items (I).Actual.Token.Length) & ASCII.LF);
      end loop;
      for I in 1 .. Lifecycle.Ret_Count loop
         Append
           (Buf,
            "RETIRE " &
            Lifecycle.Ret_Items (I).Scheduled.Token.Value
              (1 .. Lifecycle.Ret_Items (I).Scheduled.Token.Length) & ASCII.LF);
      end loop;
      for I in 1 .. Lifecycle.Repl_Count loop
         Append
           (Buf,
            "REPLACE " &
            Lifecycle.Repl_Items (I).Original.Token.Value
              (1 .. Lifecycle.Repl_Items (I).Original.Token.Length) & " " &
            Lifecycle.Repl_Items (I).Replaced_By.Token.Value
              (1 .. Lifecycle.Repl_Items (I).Replaced_By.Token.Length) & ASCII.LF);
      end loop;

      if Write_File_Atomically (Path, To_String (Buf), Err_Buf, Err_Len) then
         Result.Success := True;
      else
         Set_Error (Err_Buf (1 .. Err_Len));
      end if;

      return Result;
   end Write_Scheduled_Journal_File;

end HRA_N.Storage.Scheduled_Journal_Writer;
