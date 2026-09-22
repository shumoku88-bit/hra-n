with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with Test_Support; use Test_Support;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Application.Actual_Query; use HRA_N.Application.Actual_Query;
with HRA_N.Application.Actual_Detail_Query;
with HRA_N.Application.Frontend_Types; use HRA_N.Application.Frontend_Types;
with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;

package body Test_Actual_Query is

   procedure Run is
      Test_Dir : constant String := "/tmp/hra_n_test_actual_query";
      Paths     : constant Path_Config := Resolve_Paths (Test_Dir);
      Loam_Path : constant String := Test_Dir & "/actual.loam";
      Focus_Day : constant Date_Type := (Year => 2026, Month => 9, Day => 11);
      Error     : String (1 .. 160) := [others => ' '];
      Error_Len : Natural := 0;

      function Id_At (View : Actual_View; Index : Positive) return String is
        (View.Rows (Index).Event_Id.Value
           (1 .. View.Rows (Index).Event_Id.Length));
   begin
      if Ada.Directories.Exists (Test_Dir) then
         Ada.Directories.Delete_Tree (Test_Dir);
      end if;
      Ada.Directories.Create_Path (Test_Dir);

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-100 food:100 ""Breakfast""" & ASCII.LF &
            "TX e0002 2026-09-12 cash:-200 food:200 ""Dinner""" & ASCII.LF &
            "TX e0003 2026-09-11 cash:-300 food:300 @meal ""Lunch"" relation:r3" & ASCII.LF,
            Error,
            Error_Len),
         "Actual query fixture journal publishes");

      declare
         View : constant Actual_View :=
           Execute
             (Paths,
              (Scope        => Scope_Selected_Day,
               Selected_Day => Focus_Day,
               Ordering     => Order_Newest_First));
      begin
         Assert (View.Status = Query_Complete, "Selected-day Actual query is complete");
         Assert_Equal_Int (2, Long_Long_Integer (View.Row_Count),
                           "Selected-day Actual query filters by occurrence date");
         Assert (Id_At (View, 1) = "e0003", "Newest source row on equal date is first");
         Assert (Id_At (View, 2) = "e0001", "Older source row on equal date is second");
         Assert (View.Rows (1).Description.Length = 5,
                 "Actual query retains description evidence");
      end;

      Assert
        (Write_File_Atomically
           (Loam_Path,
            "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF &
            "TX" & ASCII.HT & "e0001" & ASCII.HT & "2026-09-11" &
              ASCII.HT & "DESC" & ASCII.HT & "Breakfast" & ASCII.LF &
            "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" &
              ASCII.HT & "-100" & ASCII.LF &
            "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" &
              ASCII.HT & "100" & ASCII.LF &
            "ENDTX" & ASCII.LF &
            "TX" & ASCII.HT & "e0002" & ASCII.HT & "2026-09-12" &
              ASCII.HT & "DESC" & ASCII.HT & "Dinner" & ASCII.LF &
            "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" &
              ASCII.HT & "-200" & ASCII.LF &
            "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" &
              ASCII.HT & "200" & ASCII.LF &
            "ENDTX" & ASCII.LF &
            "TX" & ASCII.HT & "e0003" & ASCII.HT & "2026-09-11" &
              ASCII.HT & "DESC" & ASCII.HT & "Lunch" & ASCII.LF &
            "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" &
              ASCII.HT & "-300" & ASCII.LF &
            "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" &
              ASCII.HT & "300" & ASCII.LF &
            "ENDTX" & ASCII.LF,
            Error,
            Error_Len),
         "Loam Actual query fixture publishes");

      declare
         View : constant Actual_View :=
           Execute_Loam_Actual
             (Loam_Path,
              (Scope        => Scope_Selected_Day,
               Selected_Day => Focus_Day,
               Ordering     => Order_Newest_First));
      begin
         Assert
           (View.Status = Query_Complete,
            "Loam canonical selected-day Actual query is complete");
         Assert_Equal_Int
           (2, Long_Long_Integer (View.Row_Count),
            "Loam canonical query filters by occurrence date");
         Assert
           (Id_At (View, 1) = "e0003",
            "Loam canonical query preserves newest equal-date source order");
         Assert
           (Id_At (View, 2) = "e0001",
            "Loam canonical query preserves older equal-date source order");
         Assert
           (View.Rows (1).Description.Length = 5,
            "Loam canonical query retains description evidence");
      end;

      declare
         Detail : constant
           HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
             HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
               (Loam_Path, Make_Token ("e0003"));
      begin
         Assert
           (Detail.Status = Query_Complete,
            "Loam Actual detail resolves identity through bound replay");
         Assert_Equal_Int
           (2, Long_Long_Integer (Detail.Effect_Count),
            "Loam replay detail retains every Effect");
         Assert
           (Detail.Effects (1).Amount = -300,
            "Loam replay detail retains exact signed amount");
         Assert
           (Equal_Token (Detail.Effects (2).Locus, Make_Token ("food")),
            "Loam replay detail retains effect locus");
         Assert
           (Detail.Description.Length = 5,
            "Loam replay detail uses admitted description from same snapshot");
         Assert
           (Detail.Has_Date
            and then Equal_Date
              (Detail.Valid_On, (Year => 2026, Month => 9, Day => 11)),
            "Loam replay detail uses admitted occurrence date from same snapshot");
         Assert
           (not Detail.Links.Success,
            "Loam replay detail does not mix transitional journal relation links");
      end;

      declare
         Missing : constant
           HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
             HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
               (Loam_Path, Make_Token ("absent"));
      begin
         Assert
           (Missing.Status = Query_Rejected,
            "Loam replay detail rejects absent identity");
         Assert
           (Missing.Diagnostic_Len > 0,
            "Loam replay detail absent identity carries diagnostic");
      end;

      declare
         View : constant Actual_View :=
           Execute
             (Paths,
              (Scope        => Scope_All,
               Selected_Day => Focus_Day,
               Ordering     => Order_Oldest_First));
      begin
         Assert_Equal_Int (3, Long_Long_Integer (View.Row_Count),
                           "All Actual query retains every row");
         Assert (Id_At (View, 1) = "e0001", "Oldest query starts with first day/source row");
         Assert (Id_At (View, 2) = "e0003", "Oldest query preserves equal-date source order");
         Assert (Id_At (View, 3) = "e0002", "Oldest query ends with later day");
      end;

      declare
         Detail : constant HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
           HRA_N.Application.Actual_Detail_Query.Execute
             (Paths, Make_Token ("e0003"));
      begin
         Assert (Detail.Status = Query_Complete, "Actual detail resolves selected identity");
         Assert_Equal_Int (2, Long_Long_Integer (Detail.Effect_Count),
                           "Actual detail retains every effect");
         Assert (Detail.Effects (1).Amount = -300,
                 "Actual detail retains exact signed amount");
         Assert (Equal_Token (Detail.Effects (2).Locus, Make_Token ("food")),
                 "Actual detail retains effect locus");
         Assert (Detail.Description.Length = 5,
                 "Actual detail retains description");
         Assert (Detail.Has_Purpose
                 and then Equal_Token (Detail.Purpose, Make_Token ("meal")),
                 "Actual detail exposes purpose metadata");
         Assert (Detail.Has_Relation
                 and then Equal_Token (Detail.Relation, Make_Token ("r3")),
                 "Actual detail exposes relation metadata");
         Assert (not Detail.Is_Superseded,
                 "Unsuperseded transaction reports Is_Superseded = False");
      end;

      Assert
        (Write_File_Atomically
           (Journal_Path_Str (Paths),
            "TX e0001 2026-09-11 cash:-100 food:100 ""Breakfast""" & ASCII.LF &
            "TX e0002 2026-09-12 cash:-200 food:200 ""Dinner""" & ASCII.LF &
            "TX e0003 2026-09-11 cash:-300 food:300 @meal ""Lunch"" relation:r3" & ASCII.LF &
            "TX e0004 2026-09-11 cash:-150 food:150 ""Corrected Breakfast"" replaces:e0001" & ASCII.LF,
            Error,
            Error_Len),
         "Actual query replacement journal publishes");

      declare
         Old_Detail : constant HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
           HRA_N.Application.Actual_Detail_Query.Execute
             (Paths, Make_Token ("e0001"));
         New_Detail : constant HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
           HRA_N.Application.Actual_Detail_Query.Execute
             (Paths, Make_Token ("e0004"));
      begin
         Assert (Old_Detail.Is_Superseded
                 and then Equal_Token (Old_Detail.Superseded_By, Make_Token ("e0004")),
                 "Superseded transaction reports Is_Superseded = True with successor id");
         Assert (not New_Detail.Is_Superseded,
                 "Replacement transaction reports Is_Superseded = False");
         Assert (New_Detail.Has_Replaces
                 and then Equal_Token (New_Detail.Replaces, Make_Token ("e0001")),
                 "Replacement transaction reports replaced target identity");
      end;

      Assert
        (Write_File_Atomically
           (Loam_Path,
            "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1" & ASCII.LF &
            "TX" & ASCII.HT & "bad" & ASCII.HT & "2026-09-11" &
              ASCII.HT & "NODESC" & ASCII.LF &
            "DATE-REV" & ASCII.HT & "r1" & ASCII.HT & "2026-09-12" &
              ASCII.HT & "REPLACES" & ASCII.HT & "ROOT" & ASCII.LF &
            "ENDTX" & ASCII.LF,
            Error,
            Error_Len),
         "Unsupported Loam Actual query fixture publishes");

      declare
         Rejected : constant Actual_View :=
           Execute_Loam_Actual
             (Loam_Path,
              (Scope        => Scope_All,
               Selected_Day => Focus_Day,
               Ordering     => Order_Newest_First));
      begin
         Assert
           (Rejected.Status = Query_Rejected,
            "Loam canonical Actual query fails closed on unsupported provenance");
         Assert
           (Rejected.Diagnostic_Len > 0,
            "Rejected Loam canonical query carries diagnostic");
      end;

      declare
         Rejected_Detail : constant
           HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
             HRA_N.Application.Actual_Detail_Query.Execute_Loam_Actual
               (Loam_Path, Make_Token ("bad"));
      begin
         Assert
           (Rejected_Detail.Status = Query_Rejected,
            "Loam replay detail fails closed when semantic admission fails");
         Assert
           (Rejected_Detail.Diagnostic_Len > 0,
            "Rejected Loam replay detail carries diagnostic");
      end;

      declare
         Missing : constant HRA_N.Application.Actual_Detail_Query.Actual_Detail_View :=
           HRA_N.Application.Actual_Detail_Query.Execute
             (Paths, Make_Token ("absent"));
      begin
         Assert (Missing.Status = Query_Rejected,
                 "Actual detail rejects identity absent after re-read");
      end;

      declare
         View : constant Actual_View :=
           Execute
             (Resolve_Paths (Test_Dir & "/missing"),
              (Scope        => Scope_All,
               Selected_Day => Focus_Day,
               Ordering     => Order_Newest_First));
      begin
         Assert (View.Status = Query_Rejected, "Actual query rejects missing journal");
         Assert (View.Diagnostic_Len > 0, "Rejected Actual query carries diagnostic");
      end;

      declare
         procedure Write_Loam_Synthetic (Count : Positive) is
            F : Ada.Text_IO.File_Type;
         begin
            if Ada.Directories.Exists (Loam_Path) then
               Ada.Directories.Delete_File (Loam_Path);
            end if;
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Loam_Path);
            Ada.Text_IO.Put_Line (F, "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1");
            for I in 1 .. Count loop
               declare
                  I_Str : constant String := Trim (Positive'Image (I), Both);
                  D_Str : constant String :=
                    (if I <= 5 then "2026-09-12" else "2026-09-11");
               begin
                  Ada.Text_IO.Put_Line
                    (F,
                     "TX" & ASCII.HT & "e" & I_Str & ASCII.HT & D_Str &
                     ASCII.HT & "DESC" & ASCII.HT & "Memo" & I_Str);
                  Ada.Text_IO.Put_Line
                    (F, "EFFECT" & ASCII.HT & "cash" & ASCII.HT & "jpy" & ASCII.HT & "-" & I_Str);
                  Ada.Text_IO.Put_Line
                    (F, "EFFECT" & ASCII.HT & "food" & ASCII.HT & "jpy" & ASCII.HT & I_Str);
                  Ada.Text_IO.Put_Line (F, "ENDTX");
               end;
            end loop;
            Ada.Text_IO.Close (F);
         end Write_Loam_Synthetic;

         type Actual_View_Access is access Actual_View;
         procedure Free is new Ada.Unchecked_Deallocation
           (Actual_View, Actual_View_Access);

         procedure Check_1023 is
            V : Actual_View_Access :=
              new Actual_View'
                (Execute_Loam_Actual
                   (Loam_Path,
                    (Scope        => Scope_All,
                     Selected_Day => Focus_Day,
                     Ordering     => Order_Newest_First)));
         begin
            Assert
              (V.Status = Query_Complete,
               "Loam Actual query complete at 1023 events (Max - 1)");
            Assert_Equal_Int
              (1023, Long_Long_Integer (V.Row_Count),
               "1023 query rows projected");
            Free (V);
         end Check_1023;

         procedure Check_1024_All is
            V : Actual_View_Access :=
              new Actual_View'
                (Execute_Loam_Actual
                   (Loam_Path,
                    (Scope        => Scope_All,
                     Selected_Day => Focus_Day,
                     Ordering     => Order_Newest_First)));
         begin
            Assert
              (V.Status = Query_Complete,
               "Loam Actual query complete at 1024 events (Exact Max)");
            Assert_Equal_Int
              (1024, Long_Long_Integer (V.Row_Count),
               "1024 query rows projected");
            Free (V);
         end Check_1024_All;

         procedure Check_1024_Day is
            V : Actual_View_Access :=
              new Actual_View'
                (Execute_Loam_Actual
                   (Loam_Path,
                    (Scope        => Scope_Selected_Day,
                     Selected_Day => (Year => 2026, Month => 9, Day => 12),
                     Ordering     => Order_Newest_First)));
         begin
            Assert
              (V.Status = Query_Complete,
               "Selected-day query on 1024-event image is complete");
            Assert_Equal_Int
              (5, Long_Long_Integer (V.Row_Count),
               "Selected-day query retains 5 filtered rows");
            Free (V);
         end Check_1024_Day;

         procedure Check_1025 is
            V : Actual_View_Access :=
              new Actual_View'
                (Execute_Loam_Actual
                   (Loam_Path,
                    (Scope        => Scope_All,
                     Selected_Day => Focus_Day,
                     Ordering     => Order_Newest_First)));
         begin
            Assert
              (V.Status = Query_Rejected,
               "Loam Actual query rejected at 1025 events (Max + 1)");
            Assert_Equal_Int
              (0, Long_Long_Integer (V.Row_Count),
               "No partial rows returned on query rejection");
            Assert
              (V.Diagnostic_Len > 0,
               "Rejected query carries diagnostic");
            Free (V);
         end Check_1025;

      begin
         --  1023 events: Max - 1
         Write_Loam_Synthetic (1023);
         Check_1023;

         --  1024 events: Exact Max
         Write_Loam_Synthetic (1024);
         Check_1024_All;
         Check_1024_Day;

         --  1025 events: Max + 1 fails closed
         Write_Loam_Synthetic (1025);
         Check_1025;
      end;

      Ada.Directories.Delete_Tree (Test_Dir);
   end Run;

end Test_Actual_Query;
