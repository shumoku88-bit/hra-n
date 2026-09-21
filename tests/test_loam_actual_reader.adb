with Ada.Text_IO;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with Test_Support;                    use Test_Support;

package body Test_Loam_Actual_Reader is

   Path : constant String := "/tmp/hra_n_loam_actual_reader.loam";

   procedure Write_File
     (Content : String)
   is
      File : Ada.Text_IO.File_Type;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (File, Content);
      Ada.Text_IO.Close (File);
   end Write_File;

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

   function NL return String is (1 => ASCII.LF);
   function HT return String is (1 => ASCII.HT);

   procedure Run is
      Header : constant String := "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL;
   begin
      --  1. The supported normalized slice preserves anonymous/keyed Effects,
      --  base occurrence dates, descriptions, correction and exact reversal.
      Write_File
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
               else " (" & R.Error_Reason (1 .. R.Error_Len) & ")"));
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

      --  2. Retained Effect identity may not collide within one Event.
      Write_File
        (Header
         & "TX" & HT & "ev-dup-key" & HT & "2026-09-01" & HT & "NODESC" & NL
         & "KEYED-EFFECT" & HT & "same" & HT & "wallet" & HT & "jpy" & HT & "-100" & NL
         & "KEYED-EFFECT" & HT & "same" & HT & "bank" & HT & "jpy" & HT & "100" & NL
         & "ENDTX" & NL);
      Assert
        (not Read_Loam_Actual_File (Path).Success,
         "duplicate retained Effect key fails closed");

      --  3. Unsupported normalized semantics are never silently discarded.
      Write_File
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
      Write_File
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

      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Run;

end Test_Loam_Actual_Reader;
