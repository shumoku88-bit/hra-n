-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Atomic_Writer
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with GNAT.OS_Lib;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with Test_Support;                use Test_Support;

package body Test_Atomic_Writer is

   Sandbox_Dir : constant String := "/tmp/hra_n_test_atomic_writer";

   procedure Clean_Sandbox is
      Success : Boolean;
      Args    : GNAT.OS_Lib.Argument_List (1 .. 2);
   begin
      if Ada.Directories.Exists (Sandbox_Dir) then
         Args (1) := new String'("-rf");
         Args (2) := new String'(Sandbox_Dir);
         GNAT.OS_Lib.Spawn
           (Program_Name => "/bin/rm",
            Args         => Args,
            Success      => Success);
         GNAT.OS_Lib.Free (Args (1));
         GNAT.OS_Lib.Free (Args (2));
      end if;
      Ada.Directories.Create_Path (Sandbox_Dir);
   end Clean_Sandbox;

   function Read_File_String (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
      use type SIO.Count;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         if Size = 0 then
            SIO.Close (File);
            return "";
         end if;
         SIO.Read (File, Data, Last);
         SIO.Close (File);
         declare
            Res : String (1 .. Natural (Last));
            for Res'Address use Data'Address;
         begin
            return Res;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return "";
   end Read_File_String;

   task type Reader_Task (Target_Path_Len : Positive) is
      entry Start (Path : String);
      entry Stop
        (Absent_Observed  : out Natural;
         Invalid_Observed : out Natural;
         Total_Reads      : out Natural);
   end Reader_Task;

   task body Reader_Task is
      Target        : String (1 .. Target_Path_Len);
      Absent_Count  : Natural := 0;
      Invalid_Count : Natural := 0;
      Read_Count    : Natural := 0;
      Running       : Boolean := True;
   begin
      accept Start (Path : String) do
         Target := Path;
      end Start;

      while Running loop
         select
            accept Stop
              (Absent_Observed  : out Natural;
               Invalid_Observed : out Natural;
               Total_Reads      : out Natural)
            do
               Absent_Observed  := Absent_Count;
               Invalid_Observed := Invalid_Count;
               Total_Reads      := Read_Count;
               Running          := False;
            end Stop;
         else
            if not Ada.Directories.Exists (Target) then
               Absent_Count := Absent_Count + 1;
            else
               declare
                  Content : constant String := Read_File_String (Target);
               begin
                  Read_Count := Read_Count + 1;
                  if Content'Length < 8
                    or else (Content (1 .. 8) /= "INIT_VAL"
                             and then (Content'Length < 9 or else Content (1 .. 9) /= "TEST_VAL_"))
                  then
                     Invalid_Count := Invalid_Count + 1;
                  end if;
               end;
            end if;
         end select;
      end loop;
   end Reader_Task;

   procedure Run is
      Err     : String (1 .. 256) := [others => ' '];
      Err_Len : Natural := 0;
      Ok      : Boolean;
   begin
      Clean_Sandbox;

      --  Test 1: Initial write creates target and cleans up staging
      declare
         Target : constant String := Sandbox_Dir & "/nested/initial.txt";
         Stage  : constant String := Target & ".loam-stage";
      begin
         Ok := Write_File_Atomically (Target, "INITIAL_CONTENT", Err, Err_Len);
         Assert (Ok, "Initial write succeeds");
         Assert (Ada.Directories.Exists (Target), "Target file exists after initial write");
         Assert (not Ada.Directories.Exists (Stage), "Staging file absent after initial write");
         Assert (Read_File_String (Target) = "INITIAL_CONTENT", "Initial content matches exactly");
      end;

      --  Test 2: Atomic replacement overwrites content cleanly
      declare
         Target : constant String := Sandbox_Dir & "/replace.txt";
         Stage  : constant String := Target & ".loam-stage";
      begin
         Ok := Write_File_Atomically (Target, "VERSION_1", Err, Err_Len);
         Assert (Ok, "Write version 1 succeeds");
         Assert (Read_File_String (Target) = "VERSION_1", "Version 1 matches");

         Ok := Write_File_Atomically (Target, "VERSION_2", Err, Err_Len);
         Assert (Ok, "Write version 2 succeeds");
         Assert (Read_File_String (Target) = "VERSION_2", "Version 2 replaced atomically");
         Assert (not Ada.Directories.Exists (Stage), "Staging file absent after replacement");
      end;

      --  Test 3: (Atomic_Rename test removed — no longer in public API)


      --  Test 4: Failure during write preserves existing target and cleans staging
      declare
         Target_Dir : constant String := Sandbox_Dir & "/existing_dir";
         Stage      : constant String := Target_Dir & ".loam-stage";
      begin
         --  Target_Dir is a directory; POSIX rename(file, dir) will fail with EISDIR
         Ada.Directories.Create_Directory (Target_Dir);
         Ok := Write_File_Atomically (Target_Dir, "PAYLOAD", Err, Err_Len);
         Assert (not Ok, "Writing file atomically over directory target fails closed");
         Assert (Ada.Directories.Exists (Target_Dir), "Target directory preserved after failed write");
         Assert (not Ada.Directories.Exists (Stage), "Staging file cleaned up after failed write");
      end;

      --  Test 6: Concurrent reader never observes target absent or invalid
      declare
         Target  : constant String := Sandbox_Dir & "/concurrent_test.txt";
         Stage   : constant String := Target & ".loam-stage";
         Reader  : Reader_Task (Target'Length);
         Absent  : Natural;
         Invalid : Natural;
         Reads   : Natural;
      begin
         Ok := Write_File_Atomically (Target, "INIT_VAL_START", Err, Err_Len);
         Assert (Ok, "Concurrent test target initialized");

         Reader.Start (Target);

         for I in 1 .. 300 loop
            declare
               Img : constant String := Integer'Image (I);
               Val : constant String := "TEST_VAL_" & Img (2 .. Img'Last);
            begin
               Ok := Write_File_Atomically (Target, Val, Err, Err_Len);
               if not Ok then
                  Assert (False, "Atomic write failed during concurrent iteration");
               end if;
            end;
         end loop;

         Reader.Stop (Absent, Invalid, Reads);

         Assert (Reads > 50, "Concurrent reader performed multiple reads (" & Natural'Image (Reads) & ")");
         Assert (Absent = 0, "Target was never observed absent during atomic replacement");
         Assert (Invalid = 0, "Target was never observed corrupt or invalid during atomic replacement");
         Assert (not Ada.Directories.Exists (Stage), "Staging file absent after concurrent writes");
      end;
   end Run;

end Test_Atomic_Writer;
