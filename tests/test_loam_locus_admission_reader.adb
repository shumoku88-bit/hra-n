with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Test_Support; use Test_Support;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Locus_Admission_Reader;

package body Test_Loam_Locus_Admission_Reader is

   procedure Run is
      package Reader renames HRA_N.Storage.Loam_Locus_Admission_Reader;
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
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content (Header);
      begin
         Assert (R.Success and then R.Vocabulary.Count = 0,
                 "header-only canonical Locus admission is valid empty policy");
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
         type Case_Array is array (Positive range <>) of Unbounded_String;
         Cases : constant Case_Array :=
           [To_Unbounded_String ("WRONG" & NL),
            To_Unbounded_String (Header & "BROKEN" & NL),
            To_Unbounded_String
              (Header & "LOCUS" & HT & "cash" & HT & "extra" & NL),
            To_Unbounded_String
              (Header & "LOCUS" & HT & "bad" & ASCII.CR & NL),
            To_Unbounded_String
              (Header & "LOCUS" & HT & "cash" & NL &
               "LOCUS" & HT & "cash" & NL)];
      begin
         for I in Cases'Range loop
            declare
               R : constant Reader.Read_Result :=
                 Reader.Read_Content (To_String (Cases (I)));
            begin
               Assert (not R.Success and then R.Error_Len > 0,
                       "malformed canonical Locus admission case" &
                       Positive'Image (I) & " rejects");
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
         end;
      end;
   end Run;

end Test_Loam_Locus_Admission_Reader;
