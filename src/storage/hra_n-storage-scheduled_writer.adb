-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Scheduled_Writer
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;

with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body HRA_N.Storage.Scheduled_Writer is

   function Set_Error
     (Result : in out Write_Scheduled_Result;
      Msg    : String) return Write_Scheduled_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Append_Completion
     (Scheduled_Path : String;
      Target         : Scheduled_Id;
      Actual_Event   : Event_Id) return Write_Scheduled_Result
   is
      Result   : Write_Scheduled_Result;
      File     : Ada.Text_IO.File_Type;
      Buffer   : Unbounded_String := Null_Unbounded_String;
      Inserted : Boolean := False;

      Target_Str : constant String :=
        Target.Token.Value (1 .. Target.Token.Length);
      Actual_Str : constant String :=
        Actual_Event.Token.Value (1 .. Actual_Event.Token.Length);

      Comp_Row : constant String :=
        "COMPLETION" & ASCII.HT & Target_Str & ASCII.HT & Actual_Str & ASCII.LF;
   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Scheduled_Path);
      exception
         when others =>
            return Set_Error (Result, "Could not open scheduled file: " & Scheduled_Path);
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line     : constant String := Ada.Text_IO.Get_Line (File);
            Trim_Str : constant String := Trim (Line, Ada.Strings.Both);
         begin
            if Trim_Str = "END" & ASCII.HT & "Completion" and then not Inserted then
               Append (Buffer, Comp_Row);
               Inserted := True;
            end if;
            Append (Buffer, Line);
            Append (Buffer, ASCII.LF);
         end;
      end loop;

      Ada.Text_IO.Close (File);

      if not Inserted then
         return Set_Error (Result, "Could not find Completion section in scheduled file");
      end if;

      declare
         Err_Buf : String (1 .. 128) := [others => ' '];
         Err_Len : Natural := 0;
      begin
         if not Write_File_Atomically
                  (Target_Path => Scheduled_Path,
                   Content     => To_String (Buffer),
                   Error_Msg   => Err_Buf,
                   Error_Len   => Err_Len)
         then
            return Set_Error (Result, "Failed to atomically save scheduled lifecycle");
         end if;
      end;

      Result.Success := True;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Set_Error (Result, "Exception occurred while updating scheduled lifecycle");
   end Append_Completion;

   function Append_Scheduled
     (Scheduled_Path : String;
      Target         : Scheduled_Id;
      Valid_On       : Date_Type;
      From_Locus     : String;
      To_Locus       : String;
      Amount         : Quanta_Type;
      Measure        : Measure_Id) return Write_Scheduled_Result
   is
      Result   : Write_Scheduled_Result;
      File     : Ada.Text_IO.File_Type;
      Buffer   : Unbounded_String := Null_Unbounded_String;
      Inserted : Boolean := False;

      Target_Str  : constant String := Target.Token.Value (1 .. Target.Token.Length);
      Date_Str    : constant String := Format_Iso_Date (Valid_On);
      Measure_Str : constant String := Measure.Token.Value (1 .. Measure.Token.Length);
      Amount_Str  : constant String := Trim (Amount'Image, Ada.Strings.Both);

      Sched_Block : constant String :=
        "SCHEDULED" & ASCII.HT & Target_Str & ASCII.HT & Date_Str & ASCII.HT & Measure_Str & ASCII.LF &
        "CHANGE" & ASCII.HT & From_Locus & ASCII.HT & "-" & Amount_Str & ASCII.LF &
        "CHANGE" & ASCII.HT & To_Locus & ASCII.HT & Amount_Str & ASCII.LF;
   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Scheduled_Path);
      exception
         when others =>
            return Set_Error (Result, "Could not open scheduled file: " & Scheduled_Path);
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line     : constant String := Ada.Text_IO.Get_Line (File);
            Trim_Str : constant String := Trim (Line, Ada.Strings.Both);
         begin
            if Trim_Str = "END" & ASCII.HT & "Scheduled" and then not Inserted then
               Append (Buffer, Sched_Block);
               Inserted := True;
            end if;
            Append (Buffer, Line);
            Append (Buffer, ASCII.LF);
         end;
      end loop;

      Ada.Text_IO.Close (File);

      if not Inserted then
         return Set_Error (Result, "Could not find Scheduled section in scheduled file");
      end if;

      declare
         Err_Buf : String (1 .. 128) := [others => ' '];
         Err_Len : Natural := 0;
      begin
         if not Write_File_Atomically
                  (Target_Path => Scheduled_Path,
                   Content     => To_String (Buffer),
                   Error_Msg   => Err_Buf,
                   Error_Len   => Err_Len)
         then
            return Set_Error (Result, "Failed to atomically save scheduled lifecycle");
         end if;
      end;

      Result.Success := True;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Set_Error (Result, "Exception occurred while adding scheduled obligation");
   end Append_Scheduled;

   function Append_Retirement
     (Scheduled_Path : String;
      Target         : Scheduled_Id) return Write_Scheduled_Result
   is
      Result   : Write_Scheduled_Result;
      File     : Ada.Text_IO.File_Type;
      Buffer   : Unbounded_String := Null_Unbounded_String;
      Inserted : Boolean := False;

      Target_Str : constant String := Target.Token.Value (1 .. Target.Token.Length);
      Ret_Row    : constant String :=
        "RETIREMENT" & ASCII.HT & Target_Str & ASCII.LF;
   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Scheduled_Path);
      exception
         when others =>
            return Set_Error (Result, "Could not open scheduled file: " & Scheduled_Path);
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line     : constant String := Ada.Text_IO.Get_Line (File);
            Trim_Str : constant String := Trim (Line, Ada.Strings.Both);
         begin
            if Trim_Str = "END" & ASCII.HT & "Retirement" and then not Inserted then
               Append (Buffer, Ret_Row);
               Inserted := True;
            end if;
            Append (Buffer, Line);
            Append (Buffer, ASCII.LF);
         end;
      end loop;

      Ada.Text_IO.Close (File);

      if not Inserted then
         return Set_Error (Result, "Could not find Retirement section in scheduled file");
      end if;

      declare
         Err_Buf : String (1 .. 128) := [others => ' '];
         Err_Len : Natural := 0;
      begin
         if not Write_File_Atomically
                  (Target_Path => Scheduled_Path,
                   Content     => To_String (Buffer),
                   Error_Msg   => Err_Buf,
                   Error_Len   => Err_Len)
         then
            return Set_Error (Result, "Failed to atomically save scheduled lifecycle");
         end if;
      end;

      Result.Success := True;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Set_Error (Result, "Exception occurred while retiring scheduled obligation");
   end Append_Retirement;

   function Append_Replacement
     (Scheduled_Path : String;
      Source         : Scheduled_Id;
      Replacement    : Scheduled_Id) return Write_Scheduled_Result
   is
      Result   : Write_Scheduled_Result;
      File     : Ada.Text_IO.File_Type;
      Buffer   : Unbounded_String := Null_Unbounded_String;
      Inserted : Boolean := False;

      Src_Str  : constant String :=
        Source.Token.Value (1 .. Source.Token.Length);
      Repl_Str : constant String :=
        Replacement.Token.Value (1 .. Replacement.Token.Length);

      Repl_Row : constant String :=
        "REPLACEMENT" & ASCII.HT & Src_Str & ASCII.HT & Repl_Str & ASCII.LF;
   begin
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Scheduled_Path);
      exception
         when others =>
            return Set_Error (Result, "Could not open scheduled file: " & Scheduled_Path);
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line     : constant String := Ada.Text_IO.Get_Line (File);
            Trim_Str : constant String := Trim (Line, Ada.Strings.Both);
         begin
            if Trim_Str = "END" & ASCII.HT & "Replacement" and then not Inserted then
               Append (Buffer, Repl_Row);
               Inserted := True;
            end if;
            Append (Buffer, Line);
            Append (Buffer, ASCII.LF);
         end;
      end loop;

      Ada.Text_IO.Close (File);

      if not Inserted then
         return Set_Error (Result, "Could not find Replacement section in scheduled file");
      end if;

      declare
         Err_Buf : String (1 .. 128) := [others => ' '];
         Err_Len : Natural := 0;
      begin
         if not Write_File_Atomically
                  (Target_Path => Scheduled_Path,
                   Content     => To_String (Buffer),
                   Error_Msg   => Err_Buf,
                   Error_Len   => Err_Len)
         then
            return Set_Error (Result, "Failed to atomically save scheduled lifecycle");
         end if;
      end;

      Result.Success := True;
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Set_Error (Result, "Exception occurred while appending scheduled replacement");
   end Append_Replacement;

   function Quanta_Str (Q : Quanta_Type) return String is
      Img : constant String := Quanta_Type'Image (Q);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Quanta_Str;

   function Format_Scheduled_Lifecycle
     (Lifecycle : Scheduled_Lifecycle) return String
   is
      Buf : Unbounded_String := Null_Unbounded_String;
   begin
      Append (Buf, "LOAM-SCHEDULED-LIFECYCLE" & ASCII.HT & "1" & ASCII.LF);

      --  Section: Scheduled
      Append (Buf, "BEGIN" & ASCII.HT & "Scheduled" & ASCII.LF);
      Append (Buf, "LOAM-SCHEDULED-MEMORY" & ASCII.HT & "1" & ASCII.LF);
      for I in 1 .. Lifecycle.Sched_Count loop
         declare
            Occ      : constant Scheduled_Occurrence := Lifecycle.Sched_Items (I);
            Id_Str   : constant String := Occ.Id.Token.Value (1 .. Occ.Id.Token.Length);
            Date_Str : constant String := Format_Iso_Date (Occ.Expected_Day);
            Meas_Str : constant String := Occ.Measure.Token.Value (1 .. Occ.Measure.Token.Length);
         begin
            Append (Buf, "SCHEDULED" & ASCII.HT & Id_Str & ASCII.HT & Date_Str & ASCII.HT & Meas_Str & ASCII.LF);
            for C in 1 .. Occ.Changes.Count loop
               declare
                  Chg     : constant Scheduled_Change := Occ.Changes.Values (C);
                  Loc_Str : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
                  Amt_Str : constant String := Quanta_Str (Chg.Amount);
               begin
                  Append (Buf, "CHANGE" & ASCII.HT & Loc_Str & ASCII.HT & Amt_Str & ASCII.LF);
               end;
            end loop;
         end;
      end loop;
      Append (Buf, "END" & ASCII.HT & "Scheduled" & ASCII.LF);

      --  Section: Completion
      Append (Buf, "BEGIN" & ASCII.HT & "Completion" & ASCII.LF);
      Append (Buf, "LOAM-SCHEDULED-COMPLETION-MEMORY" & ASCII.HT & "1" & ASCII.LF);
      for I in 1 .. Lifecycle.Comp_Count loop
         declare
            Comp     : constant Completion_Record := Lifecycle.Comp_Items (I);
            Sch_Str  : constant String := Comp.Scheduled.Token.Value (1 .. Comp.Scheduled.Token.Length);
            Act_Str  : constant String := Comp.Actual.Token.Value (1 .. Comp.Actual.Token.Length);
         begin
            Append (Buf, "COMPLETION" & ASCII.HT & Sch_Str & ASCII.HT & Act_Str & ASCII.LF);
         end;
      end loop;
      Append (Buf, "END" & ASCII.HT & "Completion" & ASCII.LF);

      --  Section: Retirement
      Append (Buf, "BEGIN" & ASCII.HT & "Retirement" & ASCII.LF);
      Append (Buf, "LOAM-SCHEDULED-RETIREMENT-MEMORY" & ASCII.HT & "1" & ASCII.LF);
      for I in 1 .. Lifecycle.Ret_Count loop
         declare
            Ret     : constant Retirement_Record := Lifecycle.Ret_Items (I);
            Sch_Str : constant String := Ret.Scheduled.Token.Value (1 .. Ret.Scheduled.Token.Length);
         begin
            Append (Buf, "RETIREMENT" & ASCII.HT & Sch_Str & ASCII.LF);
         end;
      end loop;
      Append (Buf, "END" & ASCII.HT & "Retirement" & ASCII.LF);

      --  Section: Replacement
      Append (Buf, "BEGIN" & ASCII.HT & "Replacement" & ASCII.LF);
      Append (Buf, "LOAM-SCHEDULED-REPLACEMENT-MEMORY" & ASCII.HT & "1" & ASCII.LF);
      for I in 1 .. Lifecycle.Repl_Count loop
         declare
            Repl     : constant Replacement_Record := Lifecycle.Repl_Items (I);
            Orig_Str : constant String := Repl.Original.Token.Value (1 .. Repl.Original.Token.Length);
            New_Str  : constant String := Repl.Replaced_By.Token.Value (1 .. Repl.Replaced_By.Token.Length);
         begin
            Append (Buf, "REPLACEMENT" & ASCII.HT & Orig_Str & ASCII.HT & New_Str & ASCII.LF);
         end;
      end loop;
      Append (Buf, "END" & ASCII.HT & "Replacement" & ASCII.LF);

      return To_String (Buf);
   end Format_Scheduled_Lifecycle;

   function Write_Scheduled_Lifecycle
     (Scheduled_Path : String;
      Lifecycle      : Scheduled_Lifecycle) return Write_Scheduled_Result
   is
      Result  : Write_Scheduled_Result;
      Text    : constant String := Format_Scheduled_Lifecycle (Lifecycle);
      Err_Buf : String (1 .. 128) := [others => ' '];
      Err_Len : Natural := 0;
   begin
      if not Write_File_Atomically
               (Target_Path => Scheduled_Path,
                Content     => Text,
                Error_Msg   => Err_Buf,
                Error_Len   => Err_Len)
      then
         return Set_Error (Result, Err_Buf (1 .. Err_Len));
      end if;

      Result.Success := True;
      return Result;
   end Write_Scheduled_Lifecycle;

end HRA_N.Storage.Scheduled_Writer;
