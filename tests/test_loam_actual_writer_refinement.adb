with Ada.Directories;
with HRA_N.Core.Actual_Bounded_History;
use HRA_N.Core.Actual_Bounded_History;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Writer; use HRA_N.Storage.Loam_Actual_Writer;
with HRA_N.Storage.Loam_Actual_Writer_Refinement;
use HRA_N.Storage.Loam_Actual_Writer_Refinement;
with Test_Support; use Test_Support;

package body Test_Loam_Actual_Writer_Refinement is

   Root   : constant String := "/tmp/hra_n_loam_writer_refinement";
   Actual : constant String := Root & "/actual.loam";
   Policy : constant String := Root & "/locus-admission.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "writer refinement fixture publishes atomically");
   end Write_Atomically;

   procedure Run is
      Effects : Effect_List;
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "record-1" & HT & "2026-09-20"
         & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-10" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "10" & NL
         & "ENDTX" & NL);

      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);

      declare
         Before : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
      begin
         Assert (Before.Success, "before-image admits");

         Effects.Count := 2;
         Effects.Values (1) :=
           (Key     => No_Effect_Key,
            Locus   => (Token => Make_Token ("cash")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => -75));
         Effects.Values (2) :=
           (Key     => No_Effect_Key,
            Locus   => (Token => Make_Token ("food")),
            Measure => (Token => Make_Token ("jpy")),
            Amount  => (Quanta => 75));

         declare
            Published : constant Publish_Result :=
              Publish_Movement
                (Root,
                 (Year => 2026, Month => 9, Day => 22),
                 Make_Description ("qualified"),
                 Effects);
            After : constant Loam_Actual_Result :=
              Read_Loam_Actual_File (Actual);
            Qualified_Result : constant Qualification_Result :=
              Qualify_One_Fresh_Append
                (Before, After, 500, 501);
         begin
            Assert
              (Published.Success,
               "production canonical writer publishes qualification fixture");
            Assert
              (After.Success,
               "after-image re-admits through production reader");
            Assert
              (Qualified_Result.Status = Qualified,
               "production before/after images refine to proved writer transition");
            Assert
              (Equal_Token
                 (Id (Qualified_Result.Added).Token,
                  Make_Token ("record-2")),
               "qualification identifies exact freshly published Event");
            Assert
              (Qualified_Result.Before_Image.Count = 1
               and then Qualified_Result.After_Image.Count = 2,
               "qualification preserves exact bounded counts");
            Assert
              (Qualified_Result.After_Image.Events (1) =
                 Qualified_Result.Before_Image.Events (1),
               "qualification preserves complete prior Event");
            Assert
              (Qualified_Result.After_Image.Events (2) =
                 Qualified_Result.Added,
               "qualification binds target suffix to complete added Event");
         end;
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Actual_Writer_Refinement;
