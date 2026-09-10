-------------------------------------------------------------------------------
--  HRA-N Unit Tests: Catalog Core & Reader
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Text_IO;                  use Ada.Text_IO;

with HRA_N.Core.Types;             use HRA_N.Core.Types;
with HRA_N.Core.Catalog;           use HRA_N.Core.Catalog;
with HRA_N.Storage.Catalog_Reader; use HRA_N.Storage.Catalog_Reader;
with HRA_N.Application.Path_Resolver;
with Test_Support;                 use Test_Support;

package body Test_Catalog is

   Sandbox_Dir : constant String := "/tmp/hra_n_test_catalog";

   --  UTF-8 byte sequences (Japanese text cannot appear in Ada literals)
   Genkin_Name : constant String :=
     [Character'Val (16#E7#), Character'Val (16#8F#), Character'Val (16#BE#),
      Character'Val (16#E9#), Character'Val (16#87#), Character'Val (16#91#)];

   Henkin_Id : constant String := "income:" &
     [Character'Val (16#E8#), Character'Val (16#BF#), Character'Val (16#94#),
      Character'Val (16#E9#), Character'Val (16#87#), Character'Val (16#91#)];

   Stock_Purpose_Id : constant String :=
     [Character'Val (16#E9#), Character'Val (16#A3#), Character'Val (16#9F#),
      Character'Val (16#E8#), Character'Val (16#B2#), Character'Val (16#BB#),
      Character'Val (16#3A#),
      Character'Val (16#E3#), Character'Val (16#82#), Character'Val (16#B9#),
      Character'Val (16#E3#), Character'Val (16#83#), Character'Val (16#88#),
      Character'Val (16#E3#), Character'Val (16#83#), Character'Val (16#83#),
      Character'Val (16#E3#), Character'Val (16#82#), Character'Val (16#AF#)];

   procedure Write_File (Path : String; Content : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Content);
      Close (F);
   end Write_File;

   procedure Run is
      Entries : Entry_Array := [others => Empty_Entry];
      Mem     : Catalog_Memory;
      Ent     : Catalog_Entry;
      Found   : Boolean;
      Label_T : Token_Text;
   begin
      ----------------------------------------------------------------------
      --  1. In-memory core catalog behavior
      ----------------------------------------------------------------------
      Entries (1) :=
        (Id           => Make_Token ("cash"),
         Display_Name => Make_Token (Genkin_Name),
         Description  => Make_Description ("on-hand currency"));
      Entries (2) :=
        (Id           => Make_Token ("point"),
         Display_Name => (Length => 0, Value => [others => ' ']),
         Description  => Empty_Description);
      Mem := Make_Catalog (Entries, 2);

      Assert (Entry_Count (Mem) = 2, "Catalog holds two entries");
      Assert (Ids_Are_Unique (Mem), "Constructed catalog ids are unique");
      Assert (Has_Entry (Mem, Make_Token ("cash")), "Has_Entry finds 'cash'");
      Assert (not Has_Entry (Mem, Make_Token ("bitcoin")), "Has_Entry rejects unknown id");

      Find_Entry (Mem, Make_Token ("cash"), Ent, Found);
      Assert (Found, "Find_Entry locates 'cash'");
      Assert (Ent.Description.Length = 16, "Find_Entry preserves description");

      Find_Entry (Mem, Make_Token ("bitcoin"), Ent, Found);
      Assert (not Found, "Find_Entry reports absence honestly");

      --  Epistemically honest labels
      Label_T := Display_Label (Mem, Make_Token ("cash"));
      Assert (Label_T.Length = Genkin_Name'Length
              and then Label_T.Value (1 .. Label_T.Length) = Genkin_Name,
              "Display_Label returns curated name when evidence exists");

      Label_T := Display_Label (Mem, Make_Token ("bitcoin"));
      Assert (Equal_Token (Label_T, Make_Token ("bitcoin")),
              "Display_Label falls back to raw identity, never a placeholder");

      Label_T := Display_Label (Mem, Make_Token ("point"));
      Assert (Equal_Token (Label_T, Make_Token ("point")),
              "Display_Label falls back to raw identity when name is empty");

      ----------------------------------------------------------------------
      --  2. Reader: synthetic sandbox fixtures
      ----------------------------------------------------------------------
      if Ada.Directories.Exists (Sandbox_Dir) then
         Ada.Directories.Delete_Tree (Sandbox_Dir);
      end if;
      Ada.Directories.Create_Path (Sandbox_Dir);

      declare
         Missing : constant Read_Result :=
           Read_Catalog_File (Sandbox_Dir & "/nonexistent.tsv");
      begin
         Assert (not Missing.Success, "Missing catalog file fails honestly");
      end;

      Write_File (Sandbox_Dir & "/one-field.tsv", "cash" & ASCII.LF);
      declare
         R : constant Read_Result := Read_Catalog_File (Sandbox_Dir & "/one-field.tsv");
      begin
         Assert (not R.Success, "Single-column row is rejected");
         Assert (R.Error_Line = 1, "Single-column rejection reports line 1");
      end;

      Write_File (Sandbox_Dir & "/four-field.tsv",
                  "cash" & ASCII.HT & "n1" & ASCII.HT & "d1" & ASCII.HT & "extra" & ASCII.LF);
      declare
         R : constant Read_Result := Read_Catalog_File (Sandbox_Dir & "/four-field.tsv");
      begin
         Assert (not R.Success, "Four-column row is rejected");
      end;

      Write_File (Sandbox_Dir & "/duplicate.tsv",
                  "cash" & ASCII.HT & "n1" & ASCII.LF &
                  "cash" & ASCII.HT & "n2" & ASCII.LF);
      declare
         R : constant Read_Result := Read_Catalog_File (Sandbox_Dir & "/duplicate.tsv");
      begin
         Assert (not R.Success, "Duplicate identity is rejected fail-closed");
         Assert (R.Error_Line = 2, "Duplicate rejection reports line 2");
      end;

      Write_File (Sandbox_Dir & "/two-field.tsv",
                  "cash" & ASCII.HT & "n1" & ASCII.LF &
                  ASCII.LF &
                  "point" & ASCII.HT & "n2" & ASCII.HT & "redeemable points" & ASCII.LF);
      declare
         R : constant Read_Result := Read_Catalog_File (Sandbox_Dir & "/two-field.tsv");
      begin
         Assert (R.Success, "Two-column rows load with empty description");
         Assert (R.Catalog.Count = 2, "Blank lines are ignored");
         Find_Entry (R.Catalog, Make_Token ("cash"), Ent, Found);
         Assert (Found and then Ent.Description.Length = 0,
                 "Missing description column reads as empty");
         Find_Entry (R.Catalog, Make_Token ("point"), Ent, Found);
         Assert (Found and then Ent.Description.Length = 17,
                 "Three-column row preserves description");
      end;

      Write_File (Sandbox_Dir & "/long-id.tsv",
                  [1 .. Max_Token_Length + 1 => 'x'] & ASCII.HT & "n" & ASCII.LF);
      declare
         R : constant Read_Result := Read_Catalog_File (Sandbox_Dir & "/long-id.tsv");
      begin
         Assert (not R.Success, "Oversized identity is rejected");
      end;

      ----------------------------------------------------------------------
      --  3. Real Loam production catalogs
      ----------------------------------------------------------------------
      if Real_Data_Available then
         declare
            Locus_R : constant Read_Result :=
              Read_Catalog_File (Real_Data_Dir & "/config/locus-catalog.tsv");
         begin
            Assert (Locus_R.Success, "Real locus-catalog.tsv loads successfully");
            Assert (Locus_R.Catalog.Count = 43, "Real locus catalog holds 43 entries");
            Assert (Ids_Are_Unique (Locus_R.Catalog), "Real locus catalog ids are unique");

            Label_T := Display_Label (Locus_R.Catalog, Make_Token ("cash"));
            Assert (Label_T.Length = Genkin_Name'Length
                    and then Label_T.Value (1 .. Label_T.Length) = Genkin_Name,
                    "Real catalog maps 'cash' to its curated Japanese name");

            Assert (Has_Entry (Locus_R.Catalog, Make_Token (Henkin_Id)),
                    "Real catalog admits UTF-8 identity (income refund)");

            Find_Entry (Locus_R.Catalog, Make_Token ("historical-unclassified"), Ent, Found);
            Assert (Found and then Ent.Description.Length = 78,
                    "Longest real description (78 bytes) fits the bound");
         end;

         declare
            Purpose_R : constant Read_Result :=
              Read_Catalog_File (Real_Data_Dir & "/config/purpose-catalog.tsv");
         begin
            Assert (Purpose_R.Success, "Real purpose-catalog.tsv loads successfully");
            Assert (Purpose_R.Catalog.Count = 7, "Real purpose catalog holds 7 entries");
            Assert (Has_Entry (Purpose_R.Catalog, Make_Token (Stock_Purpose_Id)),
                    "Real purpose catalog admits UTF-8 identity (food stock)");
         end;

         ----------------------------------------------------------------------
         --  4. Path resolution integration
         ----------------------------------------------------------------------
         declare
            Paths : constant HRA_N.Application.Path_Resolver.Path_Config :=
              HRA_N.Application.Path_Resolver.Resolve_Paths (Real_Data_Dir);
         begin
            Assert (HRA_N.Application.Path_Resolver.Locus_Catalog_Path_Str (Paths) =
                    Real_Data_Dir & "/config/locus-catalog.tsv",
                    "Resolver locates locus catalog under config/");
            Assert (HRA_N.Application.Path_Resolver.Purpose_Catalog_Path_Str (Paths) =
                    Real_Data_Dir & "/config/purpose-catalog.tsv",
                    "Resolver locates purpose catalog under config/");
         end;
      end if;
   end Run;

end Test_Catalog;
