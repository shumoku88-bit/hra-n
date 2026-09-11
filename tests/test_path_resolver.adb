------------------------------------------------------------------------------
--  HRA-N Unit Tests: Path Resolver Implementation
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Text_IO;
with Test_Support;                    use Test_Support;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package body Test_Path_Resolver is

   procedure Run is
      Paths1   : constant Path_Config := Resolve_Paths ("/custom/household/path");
      Paths2   : constant Path_Config := Resolve_Paths ("");
      Test_Dir : constant String := "/tmp/hra_n_test_path_versioned";

      procedure Write_Text (Path, Text : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put (File, Text);
         Ada.Text_IO.Close (File);
      end Write_Text;
   begin
      --  1. Explicit path resolution
      Assert (Data_Dir_Str (Paths1) = "/custom/household/path",
              "Explicit data directory preserved");
      Assert (Journal_Path_Str (Paths1) = "/custom/household/path/journal.hra",
              "Journal path derived from custom data dir");
      Assert (Policy_Path_Str (Paths1) = "/custom/household/path/policy.hra",
              "Policy path derived from custom data dir");
      Assert (Scheduled_Path_Str (Paths1) = "/custom/household/path/scheduled.hra",
              "Scheduled path derived from custom data dir");

      --  2. Fallback resolution non-empty
      Assert (Data_Dir_Str (Paths2)'Length > 0, "Fallback data directory is non-empty");
      Assert (Journal_Path_Str (Paths2)'Length > 0, "Fallback journal path is non-empty");
      Assert (Policy_Path_Str (Paths2)'Length > 0, "Fallback policy path is non-empty");
      Assert (Scheduled_Path_Str (Paths2)'Length > 0, "Fallback scheduled path is non-empty");

      --  3. CURRENT selects one complete immutable generation.
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Ada.Directories.Create_Path (Test_Dir & "/.hra/generations/g00000007");
      Write_Text (Test_Dir & "/.hra/generations/g00000007/journal.hra", "");
      Write_Text (Test_Dir & "/.hra/generations/g00000007/policy.hra", "");
      Write_Text (Test_Dir & "/.hra/generations/g00000007/scheduled.hra", "");
      Write_Text (Test_Dir & "/.hra/CURRENT", "g00000007" & ASCII.LF);

      declare
         Selected : constant Path_Config := Resolve_Paths (Test_Dir);
      begin
         Assert (Selected.Resolution_Ok, "Complete selected generation resolves");
         Assert (Selected.Is_Versioned, "CURRENT marks paths versioned");
         Assert (Snapshot_Id_Str (Selected) = "g00000007", "CURRENT identity retained");
         Assert
           (Journal_Path_Str (Selected) =
              Test_Dir & "/.hra/generations/g00000007/journal.hra",
            "Journal resolves inside selected generation");
      end;

      --  4. Invalid selectors fail closed without legacy-root fallback.
      Write_Text (Test_Dir & "/.hra/CURRENT", "../escape" & ASCII.LF);
      declare
         Invalid : constant Path_Config := Resolve_Paths (Test_Dir);
      begin
         Assert (not Invalid.Resolution_Ok, "Path traversal selector is rejected");
         Assert (not Invalid.Is_Versioned, "Invalid selector is never selected");
      end;

      Write_Text
        (Test_Dir & "/.hra/CURRENT",
         "g00000007" & ASCII.LF & "g00000008" & ASCII.LF);
      declare
         Multiple : constant Path_Config := Resolve_Paths (Test_Dir);
      begin
         Assert (not Multiple.Resolution_Ok, "Multiple selector rows are rejected");
      end;

      Write_Text (Test_Dir & "/.hra/CURRENT", "g00000008" & ASCII.LF);
      declare
         Incomplete : constant Path_Config := Resolve_Paths (Test_Dir);
      begin
         Assert (not Incomplete.Resolution_Ok, "Incomplete generation is rejected");
         Assert (Incomplete.Is_Versioned, "Incomplete selected identity is retained for diagnosis");
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;

end Test_Path_Resolver;
