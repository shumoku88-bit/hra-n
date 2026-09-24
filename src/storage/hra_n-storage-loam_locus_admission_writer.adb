-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Locus_Admission_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.File_Lock;
with HRA_N.Storage.Loam_Locus_Admission_Reader;

package body HRA_N.Storage.Loam_Locus_Admission_Writer is

   package US renames Ada.Strings.Unbounded;
   package Locus_Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   function Valid_Locus_Token (Token : Token_Text) return Boolean is
   begin
      if Token.Length = 0 then
         return False;
      end if;

      for I in 1 .. Token.Length loop
         if Token.Value (I) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Locus_Token;

   function Publish_Locus
     (Root_Path : String;
      Locus     : Locus_Id) return Publish_Result
   is
      Result : Publish_Result :=
        (Success      => False,
         Locus        => Locus,
         Error_Reason => [others => ' '],
         Error_Len    => 0);

      procedure Set_Error (Msg : String) is
         Len : constant Natural :=
           Natural'Min (Msg'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Len := Len;
         Result.Error_Reason := [others => ' '];
         if Len > 0 then
            Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
         end if;
      end Set_Error;

      Locus_Name : constant String :=
        (if Locus.Token.Length > 0
         then Locus.Token.Value (1 .. Locus.Token.Length)
         else "");

      Target_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "locus-admission.loam");
      Lock_Path   : constant String :=
        Target_Path & ".loam-writer-lock";

      Lock_Handle : HRA_N.Storage.File_Lock.Lock_Handle;

      procedure Release is
      begin
         if HRA_N.Storage.File_Lock.Is_Held (Lock_Handle) then
            HRA_N.Storage.File_Lock.Release (Lock_Handle);
         end if;
      end Release;

   begin
      if Root_Path'Length = 0 then
         Set_Error ("canonical root directory must not be empty");
         return Result;
      elsif not Ada.Directories.Exists (Root_Path) then
         Set_Error ("canonical root directory does not exist: " & Root_Path);
         return Result;
      elsif not Valid_Locus_Token (Locus.Token) then
         Set_Error ("locus token is empty or contains whitespace");
         return Result;
      end if;

      if not HRA_N.Storage.File_Lock.Acquire (Lock_Path, Lock_Handle) then
         Set_Error ("could not acquire lock: " & Lock_Path);
         return Result;
      end if;

      declare
         File_Read : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Target_Path);
      begin
         if not File_Read.Success then
            Release;
            Set_Error ("cannot read locus-admission.loam in " & Root_Path);
            return Result;
         end if;

         declare
            Existing_Text : constant String :=
              US.To_String (File_Read.Content);
            Current : constant Locus_Reader.Read_Result :=
              Locus_Reader.Read_Content (Existing_Text);
         begin
            if not Current.Success then
               Release;
               Set_Error
                 ("current locus-admission.loam is malformed or unreadable: "
                  & Current.Error_Reason (1 .. Current.Error_Len));
               return Result;
            elsif Admits_Locus (Current.Vocabulary, Locus) then
               Release;
               Set_Error ("locus coordinate is already admitted: " & Locus_Name);
               return Result;
            elsif Current.Vocabulary.Count = Max_Admitted_Loci then
               Release;
               Set_Error ("maximum admitted locus capacity reached");
               return Result;
            end if;

            declare
               Needs_NL : constant Boolean :=
                 Existing_Text'Length > 0
                 and then Existing_Text (Existing_Text'Last) /= ASCII.LF;
               New_Line_Str : constant String :=
                 (if Needs_NL then NL else "")
                 & "LOCUS" & HT & Locus_Name & NL;
               Candidate : constant String :=
                 Existing_Text & New_Line_Str;
               Candidate_Check : constant Locus_Reader.Read_Result :=
                 Locus_Reader.Read_Content (Candidate);
               Write_Err : String (1 .. 128) := [others => ' '];
               Write_Len : Natural := 0;
            begin
               if not Candidate_Check.Success then
                  Release;
                  Set_Error ("candidate locus admission failed verification");
                  return Result;
               elsif not Admits_Locus (Candidate_Check.Vocabulary, Locus) then
                  Release;
                  Set_Error ("candidate image does not admit proposed locus");
                  return Result;
               elsif Candidate_Check.Vocabulary.Count /= Current.Vocabulary.Count + 1 then
                  Release;
                  Set_Error ("candidate vocabulary count mismatch");
                  return Result;
               end if;

               if not HRA_N.Storage.Atomic_Writer.Write_File_Atomically
                 (Target_Path, Candidate, Write_Err, Write_Len)
               then
                  Release;
                  Set_Error
                    ("failed atomic write to locus-admission.loam: "
                     & Write_Err (1 .. Write_Len));
                  return Result;
               end if;

               Release;
               Result.Success := True;
               return Result;
            end;
         end;
      end;

   exception
      when E : others =>
         Release;
         Set_Error ("unexpected failure in Publish_Locus: "
                    & Ada.Exceptions.Exception_Message (E));
         return Result;
   end Publish_Locus;

end HRA_N.Storage.Loam_Locus_Admission_Writer;
