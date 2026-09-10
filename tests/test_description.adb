-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Description
-------------------------------------------------------------------------------

with HRA_N.Core.Types;                use HRA_N.Core.Types;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Storage.Description_Reader; use HRA_N.Storage.Description_Reader;
with Test_Support;                    use Test_Support;

package body Test_Description is

   procedure Run is
      Desc    : Description_Text;
      Ok      : Boolean;
      Entries : Description_Entry_List;
      Mem     : Description_Memory;
      Text    : Description_Text;
      Found   : Boolean;

      Real_Path : constant String :=
        "/Users/user/Projects/moko/loam-data/movement-authority/objects/EventDescription/" &
        "31be8ee0f0e873b9bd389e7a7daaadb87f98d746d4be40249d61a900d6fd0bc4.loam";
   begin
      --  1. Unescape plain text
      Ok := Unescape_Text ("Hello World", Desc);
      Assert (Ok, "Unescape plain text");
      Assert (To_String (Desc) = "Hello World", "Value matches plain text");

      --  2. Unescape escape sequences
      Ok := Unescape_Text ("Line1\nLine2\tTab\\Backslash", Desc);
      Assert (Ok, "Unescape valid escape sequences");
      Assert
        (To_String (Desc) = "Line1" & ASCII.LF & "Line2" & ASCII.HT & "Tab\Backslash",
         "Value matches decoded escape sequences");

      --  3. Bad escape sequences rejected
      declare
         Dummy_1 : Description_Text;
         Dummy_2 : Description_Text;
      begin
         Assert (not Unescape_Text ("Bad\xEscape", Dummy_1),
                 "Unescape rejects bad escape sequence \x");
         Assert (not Unescape_Text ("TrailingBackslash\", Dummy_2),
                 "Unescape rejects trailing dangling backslash");
      end;

      --  4. Unique entries accepted
      Entries.Count := 2;
      Entries.Values (1) :=
        (Event_Id => (Token => Make_Token ("e0001")),
         Text     => Make_Description ("Grocery shopping"));
      Entries.Values (2) :=
        (Event_Id => (Token => Make_Token ("e0002")),
         Text     => Make_Description ("Coffee"));

      Assert (Event_Ids_Are_Unique (Entries), "Unique EventIds accepted in description memory");

      Mem := Make_Description_Memory (Entries);
      Assert (Entry_Count (Mem) = 2, "Description entry count is 2");

      Find_Description (Mem, (Token => Make_Token ("e0001")), Text, Found);
      Assert (Found, "Find existing e0001");
      Assert (To_String (Text) = "Grocery shopping", "Text matches e0001");

      Find_Description (Mem, (Token => Make_Token ("e9999")), Text, Found);
      Assert (not Found, "Unknown EventId not found");
      Assert (Text.Length = 0, "Unknown EventId returns empty text");

      --  5. Duplicate rejected
      Entries.Values (2) :=
        (Event_Id => (Token => Make_Token ("e0001")),
         Text     => Make_Description ("Duplicate"));
      Assert (not Event_Ids_Are_Unique (Entries), "Duplicate EventId rejected (fail-closed)");

      --  6. Real file loading and validation
      declare
         Result : constant Read_Description_Result := Read_Description_File (Real_Path);
      begin
         Assert (Result.Success, "Real EventDescription file loads successfully");
         Assert
           (Entry_Count (Result.Memory) = 588,
            "Loaded exact 588 event descriptions from real data");

         --  Spot-check ASCII entry: e0219 -> "Opening Balance"
         Find_Description
           (Result.Memory, (Token => Make_Token ("e0219")), Text, Found);
         Assert (Found, "Spot check e0219 found");
         Assert (To_String (Text) = "Opening Balance", "e0219 description is Opening Balance");

         --  Spot-check UTF-8 entry: record-28 has 12 bytes (UTF-8 "コンビニ")
         Find_Description
           (Result.Memory, (Token => Make_Token ("record-28")), Text, Found);
         Assert (Found, "Spot check record-28 found");
         Assert (Text.Length = 12, "record-28 description has expected UTF-8 length (12 bytes)");

         --  Spot-check scheduled-2 has non-empty description
         Find_Description
           (Result.Memory,
            (Token => Make_Token ("scheduled-completion:scheduled-2")),
            Text,
            Found);
         Assert (Found, "Spot check scheduled-completion:scheduled-2 found");
         Assert (Text.Length > 0, "scheduled-2 description is non-empty");
      end;
   end Run;

end Test_Description;
