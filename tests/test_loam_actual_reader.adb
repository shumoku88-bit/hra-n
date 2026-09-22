with Ada.Text_IO;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings;                      use Ada.Strings;
with Ada.Strings.Fixed;                use Ada.Strings.Fixed;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with Test_Support;                    use Test_Support;

package body Test_Loam_Actual_Reader is

   Path : constant String := "/tmp/hra_n_loam_actual_reader.loam";

   procedure Write_Synthetic_Fixture
     (Count     : Positive;
      With_Desc : Boolean := True)
   is
      File   : Ada.Text_IO.File_Type;
      Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Header);
      for I in 1 .. Count loop
         declare
            I_Str : constant String := Trim (Positive'Image (I), Both);
         begin
            if With_Desc then
               Ada.Text_IO.Put_Line
                 (File,
                  "TX" & ASCII.HT & "ev" & I_Str & ASCII.HT &
                  "2026-09-01" & ASCII.HT & "DESC" & ASCII.HT & "Memo" & I_Str);
            else
               Ada.Text_IO.Put_Line
                 (File,
                  "TX" & ASCII.HT & "ev" & I_Str & ASCII.HT &
                  "2026-09-01" & ASCII.HT & "NODESC");
            end if;
            Ada.Text_IO.Put_Line
              (File, "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT & "-" & I_Str);
            Ada.Text_IO.Put_Line
              (File, "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT & I_Str);
            Ada.Text_IO.Put_Line (File, "ENDTX");
         end;
      end loop;
      Ada.Text_IO.Close (File);
   end Write_Synthetic_Fixture;

   procedure Write_Effects_Fixture (Effect_Count : Positive) is
      File   : Ada.Text_IO.File_Type;
      Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Header);
      Ada.Text_IO.Put_Line
        (File, "TX" & ASCII.HT & "ev-eff" & ASCII.HT & "2026-09-01" & ASCII.HT & "NODESC");
      if Effect_Count mod 2 = 0 then
         for I in 1 .. Effect_Count / 2 loop
            Ada.Text_IO.Put_Line
              (File, "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT & "10");
            Ada.Text_IO.Put_Line
              (File, "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT & "-10");
         end loop;
      else
         for I in 1 .. (Effect_Count - 3) / 2 loop
            Ada.Text_IO.Put_Line
              (File, "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT & "10");
            Ada.Text_IO.Put_Line
              (File, "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT & "-10");
         end loop;
         Ada.Text_IO.Put_Line
           (File, "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT & "10");
         Ada.Text_IO.Put_Line
           (File, "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT & "20");
         Ada.Text_IO.Put_Line
           (File, "EFFECT" & ASCII.HT & "bank" & ASCII.HT & "jpy" & ASCII.HT & "-30");
      end if;
      Ada.Text_IO.Put_Line (File, "ENDTX");
      Ada.Text_IO.Close (File);
   end Write_Effects_Fixture;

   procedure Write_Desc_Fixture (Desc_Len : Positive) is
      File   : Ada.Text_IO.File_Type;
      Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";
      Desc   : constant String (1 .. Desc_Len) := [others => 'A'];
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Header);
      Ada.Text_IO.Put_Line
        (File,
         "TX" & ASCII.HT & "ev-desc" & ASCII.HT & "2026-09-01" &
         ASCII.HT & "DESC" & ASCII.HT & Desc);
      Ada.Text_IO.Put_Line
        (File, "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT & "-100");
      Ada.Text_IO.Put_Line
        (File, "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT & "100");
      Ada.Text_IO.Put_Line (File, "ENDTX");
      Ada.Text_IO.Close (File);
   end Write_Desc_Fixture;

   procedure Write_Token_Fixture (Tok_Len : Positive) is
      File   : Ada.Text_IO.File_Type;
      Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";
      Tok    : String (1 .. Tok_Len) := [others => 'x'];
   begin
      Tok (1) := 'e';
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Header);
      Ada.Text_IO.Put_Line
        (File,
         "TX" & ASCII.HT & Tok & ASCII.HT & "2026-09-01" & ASCII.HT & "NODESC");
      Ada.Text_IO.Put_Line
        (File, "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT & "-100");
      Ada.Text_IO.Put_Line
        (File, "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT & "100");
      Ada.Text_IO.Put_Line (File, "ENDTX");
      Ada.Text_IO.Close (File);
   end Write_Token_Fixture;

   procedure Write_Exact_File
     (Content : String)
   is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Content'Length));
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      for I in Content'Range loop
         Data
           (Ada.Streams.Stream_Element_Offset (I - Content'First + 1)) :=
             Ada.Streams.Stream_Element (Character'Pos (Content (I)));
      end loop;
      SIO.Create (File, SIO.Out_File, Path);
      SIO.Write (File, Data);
      SIO.Close (File);
   end Write_Exact_File;

   function NL return String is [1 => ASCII.LF];
   function HT return String is [1 => ASCII.HT];

   procedure Run is
      Header : constant String := "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL;
   begin
      --  1. The supported normalized slice preserves anonymous/keyed Effects,
      --  base occurrence dates, descriptions, correction and exact reversal.
      Write_Exact_File
        (Header
         & "TX" & HT & "ev-root" & HT & "2026-09-01" & HT & "DESC" & HT & "Root" & NL
         & "EFFECT" & HT & "wallet" & HT & "jpy" & HT & "-100" & NL
         & "EFFECT" & HT & "bank" & HT & "jpy" & HT & "100" & NL
         & "ENDTX" & NL
         & "TX" & HT & "ev-correction" & HT & "2026-09-02" & HT & "DESC" & HT & "Corrected" & NL
         & "REPLACES" & HT & "ev-root" & NL
         & "EFFECT" & HT & "wallet" & HT & "jpy" & HT & "-120" & NL
         & "EFFECT" & HT & "bank" & HT & "jpy" & HT & "120" & NL
         & "ENDTX" & NL
         & "TX" & HT & "ev-reversal" & HT & "2026-09-03" & HT & "NODESC" & NL
         & "REVERSAL-OF" & HT & "ev-correction" & NL
         & "EFFECT" & HT & "wallet" & HT & "jpy" & HT & "120" & NL
         & "KEYED-EFFECT" & HT & "k-bank" & HT & "bank" & HT & "jpy" & HT & "-120" & NL
         & "ENDTX" & NL
         & "TX" & HT & "ev-empty" & HT & "2026-09-04" & HT & "NODESC" & NL
         & "ENDTX" & NL);

      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert
           (R.Success,
            "normalized LOAM Actual supported slice reads"
            & (if R.Success or else R.Error_Len = 0 then ""
               else " (line"
                 & Natural'Image (R.Error_Line)
                 & ": "
                 & R.Error_Reason (1 .. R.Error_Len)
                 & ")"));
         if R.Success then
            Assert_Equal_Int
              (4, Long_Long_Integer (R.Events.Length),
               "all Events including neutral empty Event are retained");
            Assert_Equal_Int
              (4, Long_Long_Integer (Entry_Count (R.Validities)),
               "base occurrence dates are retained");
            Assert_Equal_Int
              (2, Long_Long_Integer (Entry_Count (R.Descriptions)),
               "descriptions remain independent retained evidence");

            declare
               Root_Ev : constant Event := R.Events.Element (1);
               Rev_Ev  : constant Event := R.Events.Element (3);
               Root_1  : constant Effect := Effect_At (Root_Ev, 1);
               Rev_2   : constant Effect := Effect_At (Rev_Ev, 2);
            begin
               Assert
                 (not Root_1.Key.Present,
                  "ordinary EFFECT remains anonymous");
               Assert
                 (Rev_2.Key.Present
                  and then Equal_Token
                    (Rev_2.Key.Value.Token, Make_Token ("k-bank")),
                  "KEYED-EFFECT retains its exact stable key");
            end;

            declare
               Successor : Event_Id;
               Reverser  : Event_Id;
               Found     : Boolean;
            begin
               Find_Successor
                 (R.Metadata,
                  (Token => Make_Token ("ev-root")),
                  Successor,
                  Found);
               Assert
                 (Found
                  and then Equal_Token
                    (Successor.Token, Make_Token ("ev-correction")),
                  "REPLACES topology is retained");

               Find_Reverser
                 (R.Metadata,
                  (Token => Make_Token ("ev-correction")),
                  Reverser,
                  Found);
               Assert
                 (Found
                  and then Equal_Token
                    (Reverser.Token, Make_Token ("ev-reversal")),
                  "REVERSAL-OF topology is retained");
            end;
         end if;
      end;

      --  1b. The same semantic admission is available directly from an
      --  already captured exact byte image, with no pathname reopen.
      declare
         Content : constant String :=
           Header
           & "TX" & HT & "ev-content" & HT & "2026-09-05" & HT & "NODESC" & NL
           & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-7" & NL
           & "EFFECT" & HT & "food" & HT & "jpy" & HT & "7" & NL
           & "ENDTX" & NL;
         R : constant Loam_Actual_Result :=
           Read_Loam_Actual_Content (Content);
      begin
         Assert
           (R.Success,
            "exact-content admission succeeds without pathname reopen");
         Assert_Equal_Int
           (1, Long_Long_Integer (R.Events.Length),
            "exact-content admission retains the Event");
         Assert
           (Equal_Token
              (Id (R.Events.Element (1)).Token, Make_Token ("ev-content")),
            "exact-content admission preserves Event identity");
      end;

      Assert
        (not Read_Loam_Actual_Content
          ("LOAM-NORMALIZED-ACTUAL" & HT & "1").Success,
         "exact-content admission still requires canonical final newline");

      --  2. Retained Effect identity may not collide within one Event.
      Write_Exact_File
        (Header
         & "TX" & HT & "ev-dup-key" & HT & "2026-09-01" & HT & "NODESC" & NL
         & "KEYED-EFFECT" & HT & "same" & HT & "wallet" & HT & "jpy" & HT & "-100" & NL
         & "KEYED-EFFECT" & HT & "same" & HT & "bank" & HT & "jpy" & HT & "100" & NL
         & "ENDTX" & NL);
      Assert
        (not Read_Loam_Actual_File (Path).Success,
         "duplicate retained Effect key fails closed");

      --  3. Unsupported normalized semantics are never silently discarded.
      Write_Exact_File
        (Header
         & "TX" & HT & "ev-date-rev" & HT & "2026-09-01" & HT & "NODESC" & NL
         & "DATE-REV" & HT & "rev-1" & HT & "2026-09-02" & HT
         & "REPLACES" & HT & "ROOT" & NL
         & "EFFECT" & HT & "wallet" & HT & "jpy" & HT & "-100" & NL
         & "EFFECT" & HT & "bank" & HT & "jpy" & HT & "100" & NL
         & "ENDTX" & NL);
      Assert
        (not Read_Loam_Actual_File (Path).Success,
         "unsupported DATE-REV fails closed rather than losing provenance");

      --  4. A reversal must be the exact physical inverse of its target.
      Write_Exact_File
        (Header
         & "TX" & HT & "ev-target" & HT & "2026-09-01" & HT & "NODESC" & NL
         & "EFFECT" & HT & "wallet" & HT & "jpy" & HT & "-100" & NL
         & "EFFECT" & HT & "bank" & HT & "jpy" & HT & "100" & NL
         & "ENDTX" & NL
         & "TX" & HT & "ev-bad-reversal" & HT & "2026-09-02" & HT & "NODESC" & NL
         & "REVERSAL-OF" & HT & "ev-target" & NL
         & "EFFECT" & HT & "wallet" & HT & "jpy" & HT & "90" & NL
         & "EFFECT" & HT & "bank" & HT & "jpy" & HT & "-90" & NL
         & "ENDTX" & NL);
      Assert
        (not Read_Loam_Actual_File (Path).Success,
         "non-inverse reversal fails closed");

      --  5. Canonical normalized Actual must end with a final newline.
      Write_Exact_File
        ("LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "ev-no-newline" & HT & "2026-09-01" & HT & "NODESC" & NL
         & "ENDTX");
      Assert
        (not Read_Loam_Actual_File (Path).Success,
         "missing final newline fails closed");

      --  6. Event count capacity boundaries: Max-1 (1023), Max (1024), Max+1 (1025).
      Write_Synthetic_Fixture (1023, With_Desc => True);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "1023 events read successfully (Max - 1)");
         Assert_Equal_Int
           (1023, Long_Long_Integer (R.Events.Length), "1023 events retained");
         Assert_Equal_Int
           (1023, Long_Long_Integer (Entry_Count (R.Validities)),
            "1023 validities retained");
         Assert_Equal_Int
           (1023, Long_Long_Integer (Entry_Count (R.Descriptions)),
            "1023 descriptions retained");
      end;

      Write_Synthetic_Fixture (1024, With_Desc => True);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "1024 events read successfully (Exact Max)");
         Assert_Equal_Int
           (1024, Long_Long_Integer (R.Events.Length), "1024 events retained");
         Assert_Equal_Int
           (1024, Long_Long_Integer (Entry_Count (R.Validities)),
            "1024 validities retained");
         Assert_Equal_Int
           (1024, Long_Long_Integer (Entry_Count (R.Descriptions)),
            "1024 descriptions retained");
      end;

      Write_Synthetic_Fixture (1025, With_Desc => True);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (not R.Success, "1025 events fail closed (Max + 1)");
         Assert
           (R.Error_Len > 0
            and then R.Error_Reason (1 .. R.Error_Len) =
              "HRA-N Actual bridge capacity exceeded",
            "1025 events carries capacity exceeded diagnostic");
         Assert (R.Error_Line > 0, "1025 events reports error line");
      end;

      --  7. Effect count boundaries: Max-1 (31), Max (32), Max+1 (33).
      Write_Effects_Fixture (31);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "31 effects read successfully (Max - 1)");
         Assert_Equal_Int
           (31, Long_Long_Integer (Effect_Count (R.Events.Element (1))),
            "31 effects retained");
      end;

      Write_Effects_Fixture (32);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "32 effects read successfully (Exact Max)");
         Assert_Equal_Int
           (32, Long_Long_Integer (Effect_Count (R.Events.Element (1))),
            "32 effects retained");
      end;

      Write_Effects_Fixture (33);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (not R.Success, "33 effects fail closed (Max + 1)");
         Assert
           (R.Error_Len > 0
            and then R.Error_Reason (1 .. R.Error_Len) =
              "too many Effects in one Event",
            "33 effects carries too many effects diagnostic");
      end;

      --  8. Description length boundaries: Max-1 (511), Max (512), Max+1 (513).
      Write_Desc_Fixture (511);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "511 chars description reads successfully (Max - 1)");
      end;

      Write_Desc_Fixture (512);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "512 chars description reads successfully (Exact Max)");
      end;

      Write_Desc_Fixture (513);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (not R.Success, "513 chars description fails closed (Max + 1)");
         Assert
           (R.Error_Len > 0
            and then R.Error_Reason (1 .. R.Error_Len) =
              "invalid Event description",
            "513 chars carries invalid description diagnostic");
      end;

      --  9. Token length boundaries: Max-1 (95), Max (96), Max+1 (97).
      Write_Token_Fixture (95);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "95 chars token reads successfully (Max - 1)");
      end;

      Write_Token_Fixture (96);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (R.Success, "96 chars token reads successfully (Exact Max)");
      end;

      Write_Token_Fixture (97);
      declare
         R : constant Loam_Actual_Result := Read_Loam_Actual_File (Path);
      begin
         Assert (not R.Success, "97 chars token fails closed (Max + 1)");
         Assert
           (R.Error_Len > 0
            and then R.Error_Reason (1 .. R.Error_Len) =
              "invalid Event identity",
            "97 chars carries invalid identity diagnostic");
      end;

      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Run;

end Test_Loam_Actual_Reader;
