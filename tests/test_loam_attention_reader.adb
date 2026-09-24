with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Storage.Loam_Attention_Reader;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;

package body Test_Loam_Attention_Reader is
   procedure Run is
      package Reader renames HRA_N.Storage.Loam_Attention_Reader;
      T : constant String := [1 => ASCII.HT];
      N : constant String := [1 => ASCII.LF];
      H : constant String := "LOAM-ATTENTION-MEMORY" & T & "1" & N;
      A : constant String := "ITEM" & T & "a" & T & "DUE_ON" & T & "2026-09-20" & T &
        "back\\slash\ttab\nline\rreturn" & N;
      B : constant String := "ITEM" & T & "b" & T & "NO_DUE_DATE" & T & "-" & T & "B" & N;
      C : constant String := "ITEM" & T & "c" & T & "DUE_UNDETERMINED" & T & "-" & T & "C" & N;
      Valid : constant String := H & A & B & C &
        "CLOSE" & T & "b" & T & "2026-09-21" & T & "RESOLVED" & N &
        "CLOSE" & T & "c" & T & "2026-09-22" & T & "DROPPED" & N;
      type Cases is array (Positive range <>) of Unbounded_String;
      Bad : constant Cases :=
        [To_Unbounded_String ("WRONG" & N),
         To_Unbounded_String (H & A & A),
         To_Unbounded_String (Valid & "CLOSE" & T & "b" & T & "2026-09-23" & T & "DROPPED" & N),
         To_Unbounded_String (H & "CLOSE" & T & "missing" & T & "2026-09-20" & T & "DROPPED" & N),
         To_Unbounded_String (H & "ITEM" & T & "a" & T & "DUE_ON" & T & "2026-02-30" & T & "a" & N),
         To_Unbounded_String (H & "ITEM" & T & "a" & T & "LATER" & T & "-" & T & "a" & N),
         To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "2026-01-01" & T & "a" & N),
         To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & "a\q" & N),
         To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & "a\" & N),
         To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & "a" & T & "extra" & N),
         To_Unbounded_String (H & "CLOSE" & T & "a" & T & "2026-09-20" & T & "OTHER" & N),
         To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & String'(1 .. 513 => 'x') & N)];
      Missing : constant String := "/tmp/hra_n_missing_attention_reader.loam";
   begin
      if Ada.Directories.Exists (Missing) then
         Ada.Directories.Delete_File (Missing);
      end if;
      declare
         R : constant Reader.Read_Result := Reader.Read_File (Missing);
      begin
         Assert (R.Success and then not R.Present, "missing Attention is unavailable");
      end;
      declare
         R : constant Reader.Read_Result := Reader.Read_Content (H);
      begin
         Assert (R.Success and then R.Present and then R.Memory.Item_Count = 0,
                 "header-only Attention is available empty");
      end;
      declare
         R : constant Reader.Read_Result := Reader.Read_Content (Valid);
      begin
         Assert (R.Success and then R.Memory.Item_Count = 3 and then R.Memory.Close_Count = 2,
                 "three due kinds and both closures decode");
         Assert (Open_Count (R.Memory) = 1 and then Is_Open (R.Memory, R.Memory.Items (1).Id),
                 "only unclosed Attention is open");
         Assert (To_String (R.Memory.Items (1).Context) =
                   "back\slash" & ASCII.HT & "tab" & ASCII.LF & "line" & ASCII.CR & "return",
                 "LOAM context escapes decode exactly");
      end;
      for I in Bad'Range loop
         declare
            R : constant Reader.Read_Result := Reader.Read_Content (To_String (Bad (I)));
         begin
            Assert (not R.Success and then R.Present and then R.Diagnostic_Len > 0,
                    "malformed Attention case" & Positive'Image (I) & " rejects");
         end;
      end loop;
   end Run;
end Test_Loam_Attention_Reader;
