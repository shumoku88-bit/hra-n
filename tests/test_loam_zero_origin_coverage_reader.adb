with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Test_Support; use Test_Support;
with HRA_N.Core.Coverage; use HRA_N.Core.Coverage;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader;

package body Test_Loam_Zero_Origin_Coverage_Reader is

   procedure Run is
      package Reader renames HRA_N.Storage.Loam_Zero_Origin_Coverage_Reader;
      HT : constant String := [1 => ASCII.HT];
      NL : constant String := [1 => ASCII.LF];
      Header : constant String := "LOAM-ZERO-ORIGIN-COVERAGE" & HT & "1" & NL;
      Missing_Path : constant String := "/tmp/hra_n_missing_zero_origin_coverage.loam";
   begin
      if Ada.Directories.Exists (Missing_Path) then
         Ada.Directories.Delete_File (Missing_Path);
      end if;

      declare
         R : constant Reader.Read_Result := Reader.Read_File (Missing_Path);
      begin
         Assert (R.Success and then not R.Present,
                 "missing canonical coverage is successful empty evidence");
         Assert_Equal_Int (0, Long_Long_Integer (Coordinate_Count (R.Coverage)),
                           "missing canonical coverage has zero coordinates");
      end;

      declare
         R : constant Reader.Read_Result := Reader.Read_Content (Header);
      begin
         Assert (R.Success and then R.Present,
                 "header-only canonical coverage is valid present evidence");
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

      declare
         type Case_Array is array (Positive range <>) of Unbounded_String;
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
         end;
      end;
   end Run;

end Test_Loam_Zero_Origin_Coverage_Reader;
