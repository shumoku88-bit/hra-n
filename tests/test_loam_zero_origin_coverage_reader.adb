with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Test_Support; use Test_Support;
with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader;

package body Test_Loam_Zero_Origin_Coverage_Reader is

   procedure Run is
      package Reader renames HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader;
      use type Reader.Coverage_Read_Status;
      HT : constant String := [1 => ASCII.HT];
      NL : constant String := [1 => ASCII.LF];
      Header : constant String := "LOAM-ZERO-ORIGIN-COVERAGE" & HT & "1" & NL;
      Missing_Path : constant String := "/tmp/hra_n_missing_zero_origin_coverage.loam";
      Dir_Path : constant String := "/tmp/hra_n_coverage_test_dir";
   begin
      if Ada.Directories.Exists (Missing_Path) then
         Ada.Directories.Delete_File (Missing_Path);
      end if;

      declare
         R : constant Reader.Read_Result := Reader.Read_File (Missing_Path);
      begin
         Assert (R.Success and then not R.Present,
                 "missing canonical coverage is successful empty evidence");
         Assert (Reader.Format_Error (R) = "",
                 "formatted error empty on success");
         Assert_Equal_Int (0, Long_Long_Integer (Coordinate_Count (R.Coverage)),
                           "missing canonical coverage has zero coordinates");
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content (Header);
      begin
         Assert (R.Success and then R.Present,
                 "header-only canonical coverage is valid present evidence");
         Assert (Reader.Format_Error (R) = "",
                 "formatted error empty on header-only success");
         Assert_Equal_Int (0, Long_Long_Integer (Coordinate_Count (R.Coverage)),
                           "header-only canonical coverage is empty");
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content
           (Header & "COORDINATE" & HT & "cash" & HT & "jpy" & NL &
            "COORDINATE" & HT & "bank account" & HT & "usd" & NL);
      begin
         Assert (R.Success and then Coordinate_Count (R.Coverage) = 2,
                 "canonical coordinates decode");
         Assert (Is_Covered
                   (R.Coverage,
                    (Locus => (Token => Make_Token ("cash")),
                     Measure => (Token => Make_Token ("jpy")))),
                 "decoded canonical coordinate is covered");
      end;

      --  Document_Empty
      declare
         R : constant Reader.Read_Result := Reader.Read_Content ("");
      begin
         Assert (not R.Success and then R.Status = Reader.Document_Empty,
                 "empty content status is Document_Empty");
         Assert (Reader.Format_Error (R)'Length > 0,
                 "Format_Error non-empty on Document_Empty");
      end;

      --  Missing_Final_Newline
      declare
         R : constant Reader.Read_Result :=
           Reader.Read_Content ("LOAM-ZERO-ORIGIN-COVERAGE" & HT & "1");
      begin
         Assert (not R.Success and then R.Status = Reader.Missing_Final_Newline,
                 "missing LF status is Missing_Final_Newline");
      end;

      declare
         type Expected_Status_Array is array (1 .. 5) of Reader.Coverage_Read_Status;
         Expected : constant Expected_Status_Array :=
           [Reader.Unsupported_Header,
            Reader.Syntax_Error,
            Reader.Syntax_Error,
            Reader.Invalid_Token,
            Reader.Duplicate_Coordinate];
         type Case_Array is array (1 .. 5) of Unbounded_String;
         Cases : constant Case_Array :=
           [To_Unbounded_String ("WRONG" & NL),
            To_Unbounded_String (Header & "BROKEN" & NL),
            To_Unbounded_String
              (Header & "COORDINATE" & HT & "cash" & HT & "jpy" & HT & "extra" & NL),
            To_Unbounded_String
              (Header & "COORDINATE" & HT & "cash" & HT & "bad" & ASCII.CR & NL),
            To_Unbounded_String
              (Header & "COORDINATE" & HT & "cash" & HT & "jpy" & NL &
               "COORDINATE" & HT & "cash" & HT & "jpy" & NL)];
      begin
         for I in Cases'Range loop
            declare
               R : constant Reader.Read_Result := Reader.Read_Content (To_String (Cases (I)));
            begin
               Assert (not R.Success and then R.Error_Len > 0,
                       "malformed canonical coverage case" & Positive'Image (I) & " rejects");
               Assert (R.Status = Expected (I),
                       "case" & Positive'Image (I) & " status matches expected");
               Assert (Reader.Format_Error (R)'Length > 0,
                       "case" & Positive'Image (I) & " Format_Error non-empty");
            end;
         end loop;
      end;

      declare
         Content : Unbounded_String := To_Unbounded_String (Header);
      begin
         for I in 1 .. Max_Coverage_Coordinates + 1 loop
            Append (Content, "COORDINATE" & HT & "locus" &
                    Integer'Image (I) & HT & "jpy" & NL);
         end loop;
         declare
            R : constant Reader.Read_Result := Reader.Read_Content (To_String (Content));
         begin
            Assert (not R.Success and then R.Error_Len > 0,
                    "canonical coverage capacity overflow rejects");
            Assert (R.Status = Reader.Capacity_Exceeded,
                    "capacity overflow status is Capacity_Exceeded");
         end;
      end;

      --  IO_Error
      if Ada.Directories.Exists (Dir_Path) then
         Ada.Directories.Delete_Tree (Dir_Path);
      end if;
      Ada.Directories.Create_Path (Dir_Path);
      declare
         R : constant Reader.Read_Result := Reader.Read_File (Dir_Path);
      begin
         Assert (not R.Success and then R.Status = Reader.IO_Error,
                 "directory path read status is IO_Error");
         Assert (Reader.Format_Error (R)'Length > 0,
                 "Format_Error non-empty on IO_Error");
      end;
      Ada.Directories.Delete_Tree (Dir_Path);
   end Run;

end Test_Loam_Zero_Origin_Coverage_Reader;
