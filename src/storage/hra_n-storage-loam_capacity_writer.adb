-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Capacity_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Capacity_Reader;

package body HRA_N.Storage.Loam_Capacity_Writer is

   package US renames Ada.Strings.Unbounded;
   package Capacity_Reader renames HRA_N.Storage.Loam_Capacity_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   function Make_Failure
     (Status  : Capacity_Publish_Status;
      Message : String) return Publish_Result
   is
      Result : Publish_Result (Success => False);
      Len    : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.Status := Status;
      Result.Error_Len := Len;
      if Len > 0 then
         Result.Error_Reason (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end if;
      return Result;
   end Make_Failure;

   function Make_Success (Id : String) return Publish_Result is
      Result : Publish_Result (Success => True);
      Len    : constant Natural :=
        Natural'Min (Id'Length, Result.Movement_Id'Length);
   begin
      Result.Movement_Len := Len;
      if Len > 0 then
         Result.Movement_Id (1 .. Len) :=
           Id (Id'First .. Id'First + Len - 1);
      end if;
      return Result;
   end Make_Success;

   function Make_Transfer_Draft
     (Source       : Capacity_Coordinate;
      Destination  : Capacity_Coordinate;
      Amount       : Quanta_Type;
      Effective_On : Date_Type;
      Currency     : Token_Text := Make_Token ("jpy")) return Capacity_Draft
   is
      Draft : Capacity_Draft;
   begin
      Draft.Effective_On := Effective_On;
      Draft.Currency     := Currency;
      Draft.Change_Count := 2;
      Draft.Changes (1)  := (Coord => Source, Amount => -Amount);
      Draft.Changes (2)  := (Coord => Destination, Amount => Amount);
      return Draft;
   end Make_Transfer_Draft;

   function Valid_Token_Syntax (Text : String) return Boolean is
   begin
      if Text'Length = 0 or else Text'Length > Max_Token_Length then
         return False;
      end if;

      for C of Text loop
         if C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Token_Syntax;

   function Publish_Capacity
     (Root_Path : String;
      Draft     : Capacity_Draft) return Publish_Result
   is
      Target_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "capacity.loam");
      Lock_Path   : constant String :=
        Target_Path & ".loam-writer-lock";

      Lock_Handle : HRA_N.Storage.File_Lock.Lock_Handle;

      procedure Release is
      begin
         if HRA_N.Storage.File_Lock.Is_Held (Lock_Handle) then
            HRA_N.Storage.File_Lock.Release (Lock_Handle);
         end if;
      end Release;

      function Fail
        (Status  : Capacity_Publish_Status;
         Message : String) return Publish_Result
      is
      begin
         Release;
         return Make_Failure (Status, Message);
      end Fail;

      Cur_Str : constant String :=
        (if Draft.Currency.Length > 0
         then Draft.Currency.Value (1 .. Draft.Currency.Length)
         else "");

   begin
      if Root_Path'Length = 0 then
         return Fail (Invalid_Root_Directory, "canonical root directory must not be empty");
      elsif not Ada.Directories.Exists (Root_Path) then
         return Fail (Invalid_Root_Directory, "canonical root directory does not exist: " & Root_Path);
      elsif Draft.Change_Count = 0 then
         return Fail (Empty_Changes, "Capacity movement changes must not be empty");
      elsif not Is_Valid_Date (Draft.Effective_On.Year,
                               Draft.Effective_On.Month,
                               Draft.Effective_On.Day)
      then
         return Fail (Invalid_Date, "Capacity effective date must be a real calendar date in YYYY-MM-DD form");
      elsif Cur_Str /= "jpy" then
         return Fail (Unsupported_Currency, "Capacity movement must be in jpy");
      end if;

      --  Validate coordinates and amounts in draft
      declare
         Sum : Long_Long_Integer := 0;
      begin
         for I in 1 .. Draft.Change_Count loop
            declare
               C : constant Capacity_Change := Draft.Changes (I);
            begin
               if C.Amount = 0 then
                  return Fail (Zero_Amount, "Capacity movement changes must have non-zero quantities");
               end if;
               Sum := Sum + Long_Long_Integer (C.Amount);

               if C.Coord.Kind = Coord_Purpose then
                  declare
                     P_Str : constant String :=
                       C.Coord.Purpose.Value (1 .. C.Coord.Purpose.Length);
                  begin
                     if not Valid_Token_Syntax (P_Str) then
                        return Fail (Invalid_Purpose_Token, "Capacity movement coordinate contains an invalid Purpose token");
                     end if;
                  end;
               end if;

               --  Duplicate coordinate check
               for J in 1 .. I - 1 loop
                  if Equal_Coordinate (C.Coord, Draft.Changes (J).Coord) then
                     return Fail (Duplicate_Coordinate, "Capacity movement changes must not contain duplicate coordinates");
                  end if;
               end loop;
            end;
         end loop;

         if Sum /= 0 then
            return Fail (Unbalanced_Changes, "Capacity movement changes must balance to zero");
         end if;
      end;

      if not HRA_N.Storage.File_Lock.Acquire (Lock_Path, Lock_Handle) then
         return Fail (Lock_Failure, "could not acquire lock: " & Lock_Path);
      end if;

      declare
         File_Exists : constant Boolean := Ada.Directories.Exists (Target_Path);
         Existing_Memory : Capacity_Memory;
         Max_Num : Natural := 0;
      begin
         if File_Exists then
            declare
               Read_Res : constant Capacity_Reader.Read_Result :=
                 Capacity_Reader.Read_File (Target_Path);
            begin
               if not Read_Res.Success then
                  return Fail
                    (Corrupt_Existing_File,
                     "cannot read capacity.loam: "
                     & Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
               end if;
               Existing_Memory := Read_Res.Capacity;

               --  Calculate maximum capacity-N id
               for I in 1 .. Existing_Memory.Movement_Count loop
                  declare
                     Id_Tok : constant Token_Text := Existing_Memory.Movements (I).Id;
                     Id_Val : constant String := Id_Tok.Value (1 .. Id_Tok.Length);
                  begin
                     if Id_Val'Length > 9 and then Id_Val (1 .. 9) = "capacity-" then
                        declare
                           Num_Str : constant String := Id_Val (10 .. Id_Val'Last);
                           All_Digits : Boolean := True;
                        begin
                           for Ch of Num_Str loop
                              if Ch not in '0' .. '9' then
                                 All_Digits := False;
                                 exit;
                              end if;
                           end loop;
                           if All_Digits and then Num_Str'Length > 0 then
                              declare
                                 N : constant Natural := Natural'Value (Num_Str);
                              begin
                                 if N > Max_Num then
                                    Max_Num := N;
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end;
         end if;

         --  Entitlement check: each Purpose must remain non-negative
         for I in 1 .. Draft.Change_Count loop
            declare
               C : constant Capacity_Change := Draft.Changes (I);
            begin
               if C.Coord.Kind = Coord_Purpose then
                  declare
                     Current_Ent : constant Quanta_Type :=
                       Entitlement_At (Existing_Memory, C.Coord, Draft.Currency);
                     Resulting   : constant Long_Long_Integer :=
                       Long_Long_Integer (Current_Ent) + Long_Long_Integer (C.Amount);
                     P_Str       : constant String :=
                       C.Coord.Purpose.Value (1 .. C.Coord.Purpose.Length);
                  begin
                     if Resulting < 0 then
                        return Fail
                          (Negative_Entitlement,
                           "Capacity Purpose '" & P_Str &
                           "' entitlement would become negative: " &
                           Trim (Long_Long_Integer'Image (Resulting), Ada.Strings.Both));
                     end if;
                  end;
               end if;
            end;
         end loop;

         --  Generate fresh ID
         declare
            Next_Num : constant Natural := Max_Num + 1;
            New_Id   : constant String :=
              "capacity-" & Trim (Natural'Image (Next_Num), Ada.Strings.Both);
            New_Content : US.Unbounded_String := US.Null_Unbounded_String;
         begin
            if File_Exists then
               declare
                  File_Read : constant HRA_N.Storage.Exact_File.Read_Result :=
                    HRA_N.Storage.Exact_File.Read_All (Target_Path);
               begin
                  if not File_Read.Success then
                     return Fail (Corrupt_Existing_File, "cannot read existing capacity.loam content");
                  end if;
                  New_Content := File_Read.Content;
               end;
            else
               New_Content := US.To_Unbounded_String
                 ("LOAM-NORMALIZED-CAPACITY" & ASCII.HT & "1" & ASCII.LF);
            end if;

            --  Append MOVEMENT block
            US.Append (New_Content, "MOVEMENT" & HT & New_Id & HT &
                                    Format_Iso_Date (Draft.Effective_On) & HT &
                                    Cur_Str & NL);

            for I in 1 .. Draft.Change_Count loop
               declare
                  C : constant Capacity_Change := Draft.Changes (I);
                  Amt_Str : constant String :=
                    Trim (Long_Long_Integer'Image (Long_Long_Integer (C.Amount)),
                          Ada.Strings.Both);
               begin
                  if C.Coord.Kind = Coord_Unallocated then
                     US.Append (New_Content, "CHANGE" & HT & "UNALLOCATED" & HT & Amt_Str & NL);
                  else
                     declare
                        P_Str : constant String :=
                          C.Coord.Purpose.Value (1 .. C.Coord.Purpose.Length);
                     begin
                        US.Append (New_Content, "CHANGE" & HT & "PURPOSE" & HT &
                                                P_Str & HT & Amt_Str & NL);
                     end;
                  end if;
               end;
            end loop;

            US.Append (New_Content, "ENDMOVEMENT" & NL);

            --  Candidate check and atomic write
            declare
               Candidate : constant String := US.To_String (New_Content);
               Candidate_Check : constant Capacity_Reader.Read_Result :=
                 Capacity_Reader.Read_Content (Candidate);
               Write_Err : String (1 .. 128) := [others => ' '];
               Write_Len : Natural := 0;
            begin
               if not Candidate_Check.Success then
                  return Fail
                    (Verification_Failure,
                     "candidate capacity document failed verification: "
                     & Candidate_Check.Error_Reason (1 .. Candidate_Check.Error_Len));
               end if;

               if not HRA_N.Storage.Atomic_Writer.Write_File_Atomically
                 (Target_Path, Candidate, Write_Err, Write_Len)
               then
                  return Fail
                    (Atomic_Write_Failure,
                     "failed atomic write to capacity.loam: "
                     & Write_Err (1 .. Write_Len));
               end if;
            end;

            --  Readback verification
            declare
               Verify_Read : constant Capacity_Reader.Read_Result :=
                 Capacity_Reader.Read_File (Target_Path);
               Found : Boolean := False;
            begin
               if not Verify_Read.Success then
                  return Fail
                    (Readback_Failure,
                     "readback verification failed: "
                     & Verify_Read.Error_Reason (1 .. Verify_Read.Error_Len));
               end if;

               for I in 1 .. Verify_Read.Capacity.Movement_Count loop
                  declare
                     M : constant Capacity_Movement := Verify_Read.Capacity.Movements (I);
                     M_Id : constant String := M.Id.Value (1 .. M.Id.Length);
                  begin
                     if M_Id = New_Id then
                        Found := True;
                        exit;
                     end if;
                  end;
               end loop;

               if not Found then
                  return Fail (Readback_Failure, "readback verification failed: published capacity movement not found");
               end if;
            end;

            Release;
            return Make_Success (New_Id);
         end;
      end;

   exception
      when E : others =>
         return Fail
           (Internal_Error,
            "unexpected exception in publish capacity: "
            & Ada.Exceptions.Exception_Message (E));
   end Publish_Capacity;

   function Format_Error (Result : Publish_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Invalid_Root_Directory => return "canonical root directory is invalid or does not exist";
            when Empty_Changes          => return "Capacity movement changes must not be empty";
            when Invalid_Date           => return "Capacity effective date must be a real calendar date in YYYY-MM-DD form";
            when Unsupported_Currency   => return "Capacity movement must be in jpy";
            when Zero_Amount            => return "Capacity movement changes must have non-zero quantities";
            when Invalid_Purpose_Token  => return "Capacity movement coordinate contains an invalid Purpose token";
            when Duplicate_Coordinate   => return "Capacity movement changes must not contain duplicate coordinates";
            when Unbalanced_Changes     => return "Capacity movement changes must balance to zero";
            when Lock_Failure           => return "could not acquire capacity writer lock";
            when Corrupt_Existing_File  => return "cannot read capacity.loam";
            when Negative_Entitlement   => return "Capacity Purpose entitlement would become negative";
            when Verification_Failure   => return "candidate capacity document failed verification";
            when Atomic_Write_Failure   => return "failed atomic write to capacity.loam";
            when Readback_Failure       => return "readback verification failed";
            when Internal_Error         => return "internal capacity writer error";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Capacity_Writer;
