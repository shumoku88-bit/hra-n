with Ada.Directories;
with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with HRA_N.Application.Canonical_Activity_Query;
use HRA_N.Application.Canonical_Activity_Query;
with HRA_N.Application.Canonical_Balance_Query;
with HRA_N.Core.Description;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with Test_Support; use Test_Support;

package body Test_Canonical_Activity_Query is

   package US renames Ada.Strings.Unbounded;

   Root   : constant String := "/tmp/hra_n_canonical_activity_query";
   Actual : constant String := Root & "/actual.loam";

   HT : constant String := [1 => ASCII.HT];
   NL : constant String := [1 => ASCII.LF];

   procedure Write_Atomically (Path : String; Content : String) is
      Error : String (1 .. 192) := [others => ' '];
      Error_Len : Natural := 0;
   begin
      Assert
        (Write_File_Atomically (Path, Content, Error, Error_Len),
         "canonical activity fixture publishes atomically");
   end Write_Atomically;

   procedure Run is
      Fixture : constant String :=
        "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL
        & "TX" & HT & "e1" & HT & "2026-09-20" & HT
        & "DESC" & HT & "original" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-100" & NL
        & "EFFECT" & HT & "food" & HT & "jpy" & HT & "100" & NL
        & "ENDTX" & NL
        & "TX" & HT & "e2" & HT & "2026-09-21" & HT
        & "DESC" & HT & "corrected" & NL
        & "REPLACES" & HT & "e1" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-120" & NL
        & "EFFECT" & HT & "food" & HT & "jpy" & HT & "120" & NL
        & "ENDTX" & NL
        & "TX" & HT & "e3" & HT & "2026-09-22" & HT
        & "DESC" & HT & "undo corrected" & NL
        & "REVERSAL-OF" & HT & "e2" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "120" & NL
        & "EFFECT" & HT & "food" & HT & "jpy" & HT & "-120" & NL
        & "ENDTX" & NL
        & "TX" & HT & "e4" & HT & "2026-09-23" & HT
        & "DESC" & HT & "independent" & NL
        & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "500" & NL
        & "EFFECT" & HT & "income" & HT & "jpy" & HT & "-500" & NL
        & "ENDTX" & NL;
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
      Write_Atomically (Actual, Fixture);

      declare
         Source : constant Browser_Snapshot := Open (Root);
      begin
         Assert (Ready (Source), "canonical browser snapshot opens");
         Assert (Diagnostic (Source) = "", "ready snapshot has no diagnostic");

         --  Mutate the backing pathname after opening the browser snapshot.
         --  Subsequent projections must continue to describe the retained
         --  admitted image rather than silently reopening actual.loam.
         Write_Atomically
           (Actual, "LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL);

         declare
            Balances :
              constant HRA_N.Application.Canonical_Balance_Query.Balance_View :=
                Balance (Source);
            Activity : constant Activity_View :=
              Activity_For
                (Source,
                 (Token => Make_Token ("food")),
                 (Token => Make_Token ("jpy")));
            Detail : constant Event_Detail_View :=
              Event_Detail_For
                (Source, (Token => Make_Token ("e2")));
         begin
            Assert
              (Balances.Success,
               "snapshot exposes retained canonical balance view");
            Assert
              (Activity.Success,
               "coordinate activity uses retained browser snapshot");
            Assert
              (Detail.Success,
               "Event detail uses retained browser snapshot");

         Assert_Equal_Int
           (3, Long_Long_Integer (Activity.Count),
            "all physical food Events remain inspectable");
         Assert_Equal_Int
           (2, Long_Long_Integer (Activity.Active_Count),
            "replacement removes only original from active count");
         Assert_Equal_Int
           (1, Long_Long_Integer (Activity.Superseded_Count),
            "superseded physical Event remains visible as evidence");

         Assert
           (Equal_Token
              (Activity.Rows (1).Event.Token, Make_Token ("e3"))
            and then
            HRA_N.Core.Validity.Format_Iso_Date
              (Activity.Rows (1).Valid_On) = "2026-09-22",
            "activity rows sort newest date first");
         Assert
           (Activity.Rows (1).Is_Reversal
            and then Equal_Token
              (Activity.Rows (1).Reverses.Token, Make_Token ("e2"))
            and then Activity.Rows (1).Net_Change = -120,
            "reversal row preserves target and coordinate change");

         Assert
           (Equal_Token
              (Activity.Rows (2).Event.Token, Make_Token ("e2"))
            and then Activity.Rows (2).Is_Replacement
            and then Equal_Token
              (Activity.Rows (2).Replaces.Token, Make_Token ("e1"))
            and then Activity.Rows (2).Has_Reverser
            and then Equal_Token
              (Activity.Rows (2).Reversed_By.Token, Make_Token ("e3")),
            "replacement row also exposes its later reverser");
         Assert
           (Activity.Rows (2).Has_Description
            and then HRA_N.Core.Description.To_String
              (Activity.Rows (2).Description) = "corrected",
            "description evidence survives activity projection");

         Assert
           (Equal_Token
              (Activity.Rows (3).Event.Token, Make_Token ("e1"))
            and then Activity.Rows (3).Is_Superseded
            and then Equal_Token
              (Activity.Rows (3).Successor.Token, Make_Token ("e2")),
            "superseded original remains inspectable with successor evidence");

         Assert
           (Equal_Token (Detail.Event.Token, Make_Token ("e2"))
            and then
              HRA_N.Core.Validity.Format_Iso_Date (Detail.Valid_On)
                = "2026-09-21"
            and then Detail.Has_Description
            and then HRA_N.Core.Description.To_String
              (Detail.Description) = "corrected",
            "Event detail preserves identity, date, and description");
         Assert_Equal_Int
           (2, Long_Long_Integer (Detail.Effect_Count),
            "Event detail exposes every physical Effect");
         Assert
           (Equal_Token
              (Detail.Effects (1).Locus.Token, Make_Token ("cash"))
            and then Equal_Token
              (Detail.Effects (1).Measure.Token, Make_Token ("jpy"))
            and then Detail.Effects (1).Amount = -120
            and then Equal_Token
              (Detail.Effects (2).Locus.Token, Make_Token ("food"))
            and then Equal_Token
              (Detail.Effects (2).Measure.Token, Make_Token ("jpy"))
            and then Detail.Effects (2).Amount = 120,
            "Event detail preserves exact Effect coordinates and quantities");
         Assert
           (Detail.Is_Replacement
            and then Equal_Token
              (Detail.Replaces.Token, Make_Token ("e1"))
            and then Detail.Has_Reverser
            and then Equal_Token
              (Detail.Reversed_By.Token, Make_Token ("e3"))
            and then not Detail.Is_Superseded,
            "Event detail preserves terminal relationship evidence");
         end;
      end;


      --  Regression for the GUI browser snapshot: retain a production-scale
      --  admitted image without placing the full 1024-entry evidence memories
      --  in the caller's stack frame.
      Ada.Directories.Create_Path (Root);
      declare
         Large : US.Unbounded_String :=
           US.To_Unbounded_String
             ("LOAM-NORMALIZED-ACTUAL" & HT & "1" & NL);
      begin
         for I in 1 .. 650 loop
            declare
               Id_Text : constant String :=
                 "bulk-" & Trim (Natural'Image (I), Ada.Strings.Both);
            begin
               US.Append
                 (Large,
                  "TX" & HT & Id_Text & HT & "2026-09-23" & HT
                  & "NODESC" & NL
                  & "EFFECT" & HT & "cash" & HT & "jpy" & HT & "-1" & NL
                  & "EFFECT" & HT & "food" & HT & "jpy" & HT & "1" & NL
                  & "ENDTX" & NL);
            end;
         end loop;

         Write_Atomically (Actual, US.To_String (Large));
      end;

      declare
         Large_Source : constant Browser_Snapshot := Open (Root);
         Large_Balance :
           constant HRA_N.Application.Canonical_Balance_Query.Balance_View :=
             Balance (Large_Source);
         Large_Activity : constant Activity_View :=
           Activity_For
             (Large_Source,
              (Token => Make_Token ("cash")),
              (Token => Make_Token ("jpy")));
      begin
         Assert
           (Ready (Large_Source),
            "650-Event canonical browser snapshot opens");
         Assert
           (Large_Balance.Success
            and then Large_Balance.Physical_Event_Count = 650,
            "large snapshot retains all physical Events");
         Assert
           (Large_Activity.Success
            and then Large_Activity.Count = 650,
            "large snapshot supports coordinate activity without reopening");
      end;

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Run;

end Test_Canonical_Activity_Query;
