with Ada.Directories;
with HRA_N.Core.Actual_Correction_Transition;
use HRA_N.Core.Actual_Correction_Transition;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Loam_Actual_Correction_Refinement;
use HRA_N.Storage.Loam_Actual_Correction_Refinement;
with HRA_N.Storage.Loam_Actual_Reader; use HRA_N.Storage.Loam_Actual_Reader;
with HRA_N.Storage.Loam_Actual_Writer; use HRA_N.Storage.Loam_Actual_Writer;
with Test_Support; use Test_Support;

package body Test_Loam_Actual_Correction_Refinement is

   Root   : constant String := "/tmp/hra_n_loam_actual_correction_refinement";
   Actual : constant String := Root & "/actual.loam";
   Policy : constant String := Root & "/locus-admission.loam";
   HT     : constant String := [1 => ASCII.HT];
   NL     : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error     : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "correction refinement fixture publishes atomically");
   end Write_Atomically;

   function Replacement_Effects (Amount : Quanta_Type) return Effect_List is
      Items : Effect_List;
   begin
      Items.Count := 2;
      Items.Values (1) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("cash")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => -Amount));
      Items.Values (2) :=
        (Key     => No_Effect_Key,
         Locus   => (Token => Make_Token ("food")),
         Measure => (Token => Make_Token ("jpy")),
         Amount  => (Quanta => Amount));
      return Items;
   end Replacement_Effects;

   procedure Run is
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Write_Atomically
        (Policy,
         "LOAM-LOCUS-ADMISSION-VOCABULARY" & HT & "1" & NL
         & "LOCUS" & HT & "cash" & NL
         & "LOCUS" & HT & "food" & NL);

      --  Begin with one already-corrected chain so this qualification checks
      --  preservation of prior correction evidence, not only the empty case.
      Write_Atomically
        (Actual,
         "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
         & "TX" & HT & "record-1" & HT & "2026-09-20" & HT & "NODESC" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-10" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "10" & NL
         & "ENDTX" & NL
         & "TX" & HT & "replacement-1" & HT & "2026-09-20"
         & HT & "DESC" & HT & "first correction" & NL
         & "REPLACES" & HT & "record-1" & NL
         & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-15" & NL
         & "EFFECT" & HT & "food" & HT & "jpy" & HT & "15" & NL
         & "ENDTX" & NL);

      declare
         Before : constant Loam_Actual_Result :=
           Read_Loam_Actual_File (Actual);
      begin
         Assert (Before.Success, "before correction image admits");

         declare
            Published : constant Publish_Result :=
              Publish_Correction
                (Root,
                 (Token => Make_Token ("replacement-1")),
                 Make_Description ("second correction"),
                 Replacement_Effects (25));
            After : constant Loam_Actual_Result :=
              Read_Loam_Actual_File (Actual);
            Qualified_Result : constant Qualification_Result :=
              Qualify_One_Current_Correction
                (Before,
                 After,
                 (Token => Make_Token ("replacement-1")),
                 900,
                 901);
         begin
            Assert
              (Published.Success,
               "production correction writer publishes qualification fixture");
            Assert
              (Published.Success
               and then Equal_Token
                 (Published.Event_Id, Make_Token ("replacement-2")),
               "production correction allocates expected fresh replacement");
            Assert
              (After.Success,
               "after correction image re-admits through production reader");
            Assert
              (Qualified_Result.Status = Qualified,
               "production before/after correction refines to proved transition");
            Assert
              (Qualified_Result.Before_Image.Edge_Count = 1
               and then Qualified_Result.After_Image.Edge_Count = 2,
               "qualification retains old edge and adds exactly one edge");
            Assert
              (Qualified_Result.Before_Image.Edges (1) =
                 Qualified_Result.After_Image.Edges (1),
               "qualification preserves complete prior correction edge");
            Assert
              (not Current_In_Frontier
                 (Qualified_Result.After_Image,
                  (Token => Make_Token ("replacement-1")))
               and then Current_In_Frontier
                 (Qualified_Result.After_Image,
                  (Token => Make_Token ("replacement-2"))),
               "qualified production transition moves current frontier");
            Assert
              (Equal_Token
                 (HRA_N.Core.Event.Id (Qualified_Result.Replacement).Token,
                  Make_Token ("replacement-2")),
               "qualification binds exact production replacement Event");
         end;
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Loam_Actual_Correction_Refinement;
