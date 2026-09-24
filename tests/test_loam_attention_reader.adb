with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Directories;
with Test_Support; use Test_Support;
with HRA_N.Storage.Loam_Attention_Reader;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;
with HRA_N.Core.Description; use HRA_N.Core.Description;

package body Test_Loam_Attention_Reader is
   procedure Run is
      package Reader renames HRA_N.Storage.Loam_Attention_Reader;
      use type Reader.Attention_Read_Status;
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
      type Case_Record is record
         Text   : Unbounded_String;
         Status : Reader.Attention_Read_Status;
      end record;
      type Cases is array (Positive range <>) of Case_Record;
      Bad : constant Cases :=
        [(Text => To_Unbounded_String ("WRONG" & N),
          Status => Reader.Unsupported_Header),
         (Text => To_Unbounded_String (H & A & A),
          Status => Reader.Conflict),
         (Text => To_Unbounded_String (Valid & "CLOSE" & T & "b" & T & "2026-09-23" & T & "DROPPED" & N),
          Status => Reader.Conflict),
         (Text => To_Unbounded_String (H & "CLOSE" & T & "missing" & T & "2026-09-20" & T & "DROPPED" & N),
          Status => Reader.Conflict),
         (Text => To_Unbounded_String (H & "ITEM" & T & "a" & T & "DUE_ON" & T & "2026-02-30" & T & "a" & N),
          Status => Reader.Invalid_Due),
         (Text => To_Unbounded_String (H & "ITEM" & T & "a" & T & "LATER" & T & "-" & T & "a" & N),
          Status => Reader.Invalid_Due),
         (Text => To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "2026-01-01" & T & "a" & N),
          Status => Reader.Invalid_Due),
         (Text => To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & "a\q" & N),
          Status => Reader.Invalid_Escape),
         (Text => To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & "a\" & N),
          Status => Reader.Invalid_Escape),
         (Text => To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & "a" & T & "extra" & N),
          Status => Reader.Syntax_Error),
         (Text => To_Unbounded_String (H & "CLOSE" & T & "a" & T & "2026-09-20" & T & "OTHER" & N),
          Status => Reader.Invalid_Closure),
         (Text => To_Unbounded_String (H & "ITEM" & T & "a" & T & "NO_DUE_DATE" & T & "-" & T & String'(1 .. 513 => 'x') & N),
          Status => Reader.Invalid_Escape)];
      Missing : constant String := "/tmp/hra_n_missing_attention_reader.loam";
   begin
      if Ada.Directories.Exists (Missing) then
         Ada.Directories.Delete_File (Missing);
      end if;
      declare
         R : constant Reader.Read_Result := Reader.Read_File (Missing);
      begin
         Assert (R.Success and then not R.Present, "missing Attention is unavailable");
         Assert (Reader.Format_Error (R) = "", "formatted error is empty on success");
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
      declare
         Overflow : Unbounded_String := To_Unbounded_String (H);
      begin
         for I in 1 .. Max_Attention_Items + 1 loop
            Append (Overflow, "ITEM" & T & "item-" &
              Integer'Image (I) & T & "NO_DUE_DATE" & T & "-" & T & "x" & N);
         end loop;
         declare
            R : constant Reader.Read_Result := Reader.Read_Content (To_String (Overflow));
         begin
            Assert (not R.Success, "Attention item capacity overflow rejects");
            Assert (R.Status = Reader.Capacity_Exceeded, "status is Capacity_Exceeded");
         end;
      end;
      declare
         Overflow : Unbounded_String := To_Unbounded_String (H & A);
      begin
         for I in 1 .. Max_Attention_Items + 1 loop
            Append (Overflow, "CLOSE" & T & "a" & T & "2026-09-21" & T & "RESOLVED" & N);
         end loop;
         declare
            R : constant Reader.Read_Result := Reader.Read_Content (To_String (Overflow));
         begin
            Assert (not R.Success, "Attention closure capacity overflow rejects");
            Assert (R.Status = Reader.Capacity_Exceeded, "status is Capacity_Exceeded");
         end;
      end;
      for I in Bad'Range loop
         declare
            R : constant Reader.Read_Result := Reader.Read_Content (To_String (Bad (I).Text));
         begin
            Assert (not R.Success and then R.Present and then R.Diagnostic_Len > 0,
                    "malformed Attention case" & Positive'Image (I) & " rejects");
            Assert (R.Status = Bad (I).Status,
                    "malformed Attention case" & Positive'Image (I) & " matches expected status");
            Assert (Reader.Format_Error (R)'Length > 0,
                    "Format_Error returns non-empty for error case" & Positive'Image (I));
         end;
      end loop;
   end Run;
end Test_Loam_Attention_Reader;
