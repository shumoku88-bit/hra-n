-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Scheduled_Journal_Writer
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded;         use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;             use Ada.Strings.Fixed;
with HRA_N.Core.Types;              use HRA_N.Core.Types;
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
      Append (Buf, "# Format: SCHED <id> <due-date> <flows...> status:<status>" & ASCII.LF & ASCII.LF);

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

            --  Resolve status
            if Is_Completed (Lifecycle, Occ.Id) then
               declare
                  Ref_Id : String (1 .. Max_Token_Length) := [others => ' '];
                  Ref_Len : Natural := 0;
               begin
                  for K in 1 .. Lifecycle.Comp_Count loop
                     if Equal_Token (Lifecycle.Comp_Items (K).Scheduled.Token, Occ.Id.Token) then
                        Ref_Len := Lifecycle.Comp_Items (K).Actual.Token.Length;
                        Ref_Id (1 .. Ref_Len) := Lifecycle.Comp_Items (K).Actual.Token.Value (1 .. Ref_Len);
                        exit;
                     end if;
                  end loop;

                  Append (Buf, " status:completed:");
                  Append (Buf, Ref_Id (1 .. Ref_Len));
               end;
            elsif Is_Retired (Lifecycle, Occ.Id) then
               Append (Buf, " status:retired");
            elsif Is_Replaced (Lifecycle, Occ.Id) then
               declare
                  Succ_Id : String (1 .. Max_Token_Length) := [others => ' '];
                  Succ_Len : Natural := 0;
               begin
                  for K in 1 .. Lifecycle.Repl_Count loop
                     if Equal_Token (Lifecycle.Repl_Items (K).Original.Token, Occ.Id.Token) then
                        Succ_Len := Lifecycle.Repl_Items (K).Replaced_By.Token.Length;
                        Succ_Id (1 .. Succ_Len) := Lifecycle.Repl_Items (K).Replaced_By.Token.Value (1 .. Succ_Len);
                        exit;
                     end if;
                  end loop;

                  Append (Buf, " status:replaced-by:");
                  Append (Buf, Succ_Id (1 .. Succ_Len));
               end;
            else
               Append (Buf, " status:open");
            end if;

            Append (Buf, ASCII.LF);
         end;
      end loop;

      if Write_File_Atomically (Path, To_String (Buf), Err_Buf, Err_Len) then
         Result.Success := True;
      else
         Set_Error (Err_Buf (1 .. Err_Len));
      end if;

      return Result;
   end Write_Scheduled_Journal_File;

end HRA_N.Storage.Scheduled_Journal_Writer;
