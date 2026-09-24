with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Test_Support; use Test_Support;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Locus_Admission_Reader;

package body Test_Loam_Locus_Admission_Reader is

   procedure Run is
      package Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;
      use type Reader.Locus_Read_Status;
      HT : constant String := [1 => ASCII.HT];
      NL : constant String := [1 => ASCII.LF];
      Header : constant String :=
        "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL;
      Missing_Path : constant String :=
        "/tmp/hra_n_missing_locus_admission.loam";
   begin
      if Ada.Directories.Exists (Missing_Path) then
         Ada.Directories.Delete_File (Missing_Path);
      end if;

      declare
         R : constant Reader.Read_Result := Reader.Read_File (Missing_Path);
      begin
         Assert (not R.Success and then R.Error_Len > 0,
                 "missing canonical Locus admission authority rejects");
         Assert (R.Status = Reader.IO_Error,
                 "missing authority status is IO_Error");
         Assert (Reader.Format_Error (R)'Length > 0,
                 "formatted error is non-empty for IO_Error");
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content (Header);
      begin
         Assert (R.Success and then R.Vocabulary.Count = 0,
                 "header-only canonical Locus admission is valid empty policy");
         Assert (Reader.Format_Error (R) = "",
                 "formatted error is empty on success");
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content
           (Header & "LOCUS" & HT & "cash" & NL &
            "LOCUS" & HT & "food" & NL);
      begin
         Assert (R.Success and then R.Vocabulary.Count = 2,
                 "canonical Locus admission rows decode");
         Assert (Admits_Locus
                   (R.Vocabulary, (Token => Make_Token ("cash")))
                 and then Admits_Locus
                   (R.Vocabulary, (Token => Make_Token ("food"))),
                 "decoded canonical Loci are admitted");
      end;

      declare
         type Case_Record is record
            Text   : Unbounded_String;
            Status : Reader.Locus_Read_Status;
         end record;
         type Case_Array is array (Positive range <>) of Case_Record;
         Cases : constant Case_Array :=
           [(Text => To_Unbounded_String ("WRONG" & NL),
             Status => Reader.Unsupported_Header),
            (Text => To_Unbounded_String (Header & "BROKEN" & NL),
             Status => Reader.Syntax_Error),
            (Text => To_Unbounded_String
               (Header & "LOCUS" & HT & "cash" & HT & "extra" & NL),
             Status => Reader.Invalid_Token),
            (Text => To_Unbounded_String
               (Header & "LOCUS" & HT & "bad" & ASCII.CR & NL),
             Status => Reader.Invalid_Token),
            (Text => To_Unbounded_String
               (Header & "LOCUS" & HT & "cash" & NL &
                "LOCUS" & HT & "cash" & NL),
             Status => Reader.Duplicate_Token)];
      begin
         for I in Cases'Range loop
            declare
               R : constant Reader.Read_Result :=
                 Reader.Read_Content (To_String (Cases (I).Text));
            begin
               Assert (not R.Success and then R.Error_Len > 0,
                       "malformed canonical Locus admission case" &
                       Positive'Image (I) & " rejects");
               Assert (R.Status = Cases (I).Status,
                       "malformed canonical Locus admission case" &
                       Positive'Image (I) & " matches expected status");
            end;
         end loop;
      end;

      declare
         Content : Unbounded_String := To_Unbounded_String (Header);
      begin
         for I in 1 .. Max_Admitted_Loci + 1 loop
            Append (Content, "LOCUS" & HT & "locus" &
                    Integer'Image (I) & NL);
         end loop;
         declare
            R : constant Reader.Read_Result :=
              Reader.Read_Content (To_String (Content));
         begin
            Assert (not R.Success and then R.Error_Len > 0,
                    "canonical Locus admission capacity overflow rejects");
            Assert (R.Status = Reader.Capacity_Exceeded,
                    "capacity overflow status is Capacity_Exceeded");
         end;
      end;
   end Run;

end Test_Loam_Locus_Admission_Reader;
