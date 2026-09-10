-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Review
-------------------------------------------------------------------------------

with HRA_N.UI.Output;              use HRA_N.UI.Output;
with Ada.Calendar;
with HRA_N.Core.Types;              use HRA_N.Core.Types;
with HRA_N.Core.Event;              use HRA_N.Core.Event;
with HRA_N.Storage.Validity_Reader; use HRA_N.Storage.Validity_Reader;

package body HRA_N.Application.Review is

   Page_Size        : constant := 10;
   Max_Review_Items : constant := 1024;

   function Get_System_Date return Date_Type is
      Now  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Y    : Ada.Calendar.Year_Number;
      M    : Ada.Calendar.Month_Number;
      D    : Ada.Calendar.Day_Number;
      Secs : Ada.Calendar.Day_Duration;
   begin
      Ada.Calendar.Split (Now, Y, M, D, Secs);
      return Make_Date (Y, M, D);
   end Get_System_Date;

   function Parse_Query
     (Query_Str : String;
      Today     : Date_Type;
      Query     : out Review_Query) return Boolean
   is
   begin
      if Query_Str = "t" then
         Query := (Kind => Query_Week, Ending_Date => Today);
         return True;
      elsif Query_Str = "u" then
         Query := (Kind => Query_Undated);
         return True;
      elsif Query_Str'Length = 10 and then Query_Str (Query_Str'First + 4) = '-' then
         declare
            D : Date_Type;
         begin
            if Parse_Iso_Date (Query_Str, D) then
               Query := (Kind => Query_Day, Day_Date => D);
               return True;
            end if;
         end;
      elsif Query_Str'Length > 1 and then Query_Str (Query_Str'First) = '/' then
         declare
            Len : constant Natural := Query_Str'Length - 1;
         begin
            if Len <= Max_Search_Length then
               Query := (Kind => Query_Search,
                         Search_Len => Len,
                         Search_Text => [others => ' ']);
               Query.Search_Text (1 .. Len) :=
                 Query_Str (Query_Str'First + 1 .. Query_Str'Last);
               return True;
            end if;
         end;
      end if;
      return False;
   end Parse_Query;

   function To_Lower_Char (C : Character) return Character is
     (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32) else C);

   function Case_Insensitive_Contains (Haystack, Needle : String) return Boolean is
   begin
      if Needle'Length = 0 then
         return True;
      elsif Needle'Length > Haystack'Length then
         return False;
      end if;

      for I in Haystack'First .. Haystack'Last - Needle'Length + 1 loop
         declare
            Match : Boolean := True;
         begin
            for J in Needle'Range loop
               if To_Lower_Char (Haystack (I + (J - Needle'First))) /=
                  To_Lower_Char (Needle (J))
               then
                  Match := False;
                  exit;
               end if;
            end loop;
            if Match then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Case_Insensitive_Contains;

   function Quanta_Image (Q : Quanta_Type) return String is
      Img : constant String := Quanta_Type'Image (Q);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Quanta_Image;

   function Natural_Image (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Natural_Image;

   type Review_Record is record
      Event_Idx   : Positive;
      Ev_Id       : Token_Text;
      Has_Date    : Boolean;
      Date        : Date_Type;
      Has_Desc    : Boolean;
      Description : Description_Text;
   end record;

   type Record_Array is array (1 .. Max_Review_Items) of Review_Record;
   type Index_Array  is array (1 .. Max_Review_Items) of Positive;

   function Matches_Search
     (Rec  : Review_Record;
      Ev   : Event;
      Term : String) return Boolean
   is
      Ev_Id_Str : constant String :=
        Rec.Ev_Id.Value (1 .. Rec.Ev_Id.Length);
   begin
      if Case_Insensitive_Contains (Ev_Id_Str, Term) then
         return True;
      end if;

      if Rec.Has_Date then
         declare
            Date_Str : constant Iso_Date_String := Format_Iso_Date (Rec.Date);
         begin
            if Case_Insensitive_Contains (Date_Str, Term) then
               return True;
            end if;
         end;
      end if;

      if Rec.Has_Desc then
         declare
            Desc_Str : constant String := To_String (Rec.Description);
         begin
            if Case_Insensitive_Contains (Desc_Str, Term) then
               return True;
            end if;
         end;
      end if;

      for I in 1 .. Effect_Count (Ev) loop
         declare
            Eff   : constant Effect := Effect_At (Ev, I);
            Locus : constant String :=
              Eff.Locus.Token.Value (1 .. Eff.Locus.Token.Length);
            Meas  : constant String :=
              Eff.Measure.Token.Value (1 .. Eff.Measure.Token.Length);
            Qty   : constant String := Quanta_Image (Eff.Amount.Quanta);
         begin
            if Case_Insensitive_Contains (Locus, Term)
              or else Case_Insensitive_Contains (Meas, Term)
              or else Case_Insensitive_Contains (Qty, Term)
            then
               return True;
            end if;
         end;
      end loop;

      return False;
   end Matches_Search;

   function Is_Earlier_In_Review (Left, Right : Review_Record) return Boolean is
   begin
      if Left.Has_Date and then Right.Has_Date then
         if Equal_Date (Left.Date, Right.Date) then
            return Token_Less (Left.Ev_Id, Right.Ev_Id);
         else
            return Date_Greater (Left.Date, Right.Date);
         end if;
      elsif Left.Has_Date and then not Right.Has_Date then
         return True;
      elsif not Left.Has_Date and then Right.Has_Date then
         return False;
      else
         return Token_Less (Left.Ev_Id, Right.Ev_Id);
      end if;
   end Is_Earlier_In_Review;

   procedure Format_Summary
     (Rec    : in  Review_Record;
      Ev     : in  Event;
      Output : out String;
      Length : out Natural)
   is
      Buf : String (1 .. 1024) := [others => ' '];
      Pos : Natural := 0;

      procedure Append (S : String) is
      begin
         if Pos + S'Length <= Buf'Last then
            Buf (Pos + 1 .. Pos + S'Length) := S;
            Pos := Pos + S'Length;
         end if;
      end Append;

      Eff_Count : constant Natural := Effect_Count (Ev);
   begin
      --  1. Description
      if Rec.Has_Desc and then Rec.Description.Length > 0 then
         Append (To_String (Rec.Description));
      else
         Append ("(no description)");
      end if;

      Append ("  | ");

      --  2. Effects (up to 2)
      if Eff_Count = 0 then
         Append ("(no quantity effects)");
      else
         for I in 1 .. Natural'Min (2, Eff_Count) loop
            if I > 1 then
               Append ("; ");
            end if;
            declare
               Eff   : constant Effect := Effect_At (Ev, I);
               Locus : constant String :=
                 Eff.Locus.Token.Value (1 .. Eff.Locus.Token.Length);
               Meas  : constant String :=
                 Eff.Measure.Token.Value (1 .. Eff.Measure.Token.Length);
               Qty   : constant String := Quanta_Image (Eff.Amount.Quanta);
            begin
               Append (Locus & ": " & Qty & " " & Meas);
            end;
         end loop;

         if Eff_Count > 2 then
            Append ("  (+" & Natural_Image (Eff_Count - 2) & " effects)");
         end if;
      end if;

      Output (Output'First .. Output'First + Pos - 1) := Buf (1 .. Pos);
      Length := Pos;
   end Format_Summary;

   procedure Execute_Review
     (Events       : in Event_Vectors.Vector;
      Validity     : in Validity_Memory;
      Descriptions : in Description_Memory;
      Query        : in Review_Query)
   is
      Total_Events : constant Natural := Natural (Events.Length);
      All_Records  : Record_Array;
      Match_Count  : Natural := 0;
      Undated_Cnt  : Natural := 0;

      Week_Days    : Week_Days_Array;
      Has_Week     : Boolean := False;

      Selected     : Index_Array;
   begin
      if Total_Events > Max_Review_Items then
         Put_Line ("[ERROR] Event count exceeds review capacity");
         return;
      end if;

      --  1. Populate all records with date and description evidence
      for I in 1 .. Total_Events loop
         declare
            Ev       : constant Event := Events.Element (I);
            Ev_Id    : constant Event_Id := Id (Ev);
            Date_Val : Date_Type;
            Has_D    : Boolean;
            Desc_Val : Description_Text;
            Has_Tx   : Boolean;
         begin
            Find_Occurrence_Date (Validity, Ev_Id, Date_Val, Has_D);
            Find_Description (Descriptions, Ev_Id, Desc_Val, Has_Tx);

            if not Has_D then
               Undated_Cnt := Undated_Cnt + 1;
            end if;

            All_Records (I) :=
              (Event_Idx   => I,
               Ev_Id       => Ev_Id.Token,
               Has_Date    => Has_D,
               Date        => Date_Val,
               Has_Desc    => Has_Tx,
               Description => Desc_Val);
         end;
      end loop;

      --  2. Setup week days if week or day query
      case Query.Kind is
         when Query_Week =>
            Week_Days := Previous_Days_7 (Query.Ending_Date);
            Has_Week  := True;
         when Query_Day =>
            Week_Days := Previous_Days_7 (Query.Day_Date);
            Has_Week  := True;
         when others =>
            Has_Week  := False;
      end case;

      --  3. Filter matching records
      for I in 1 .. Total_Events loop
         declare
            Rec     : constant Review_Record := All_Records (I);
            Matched : Boolean := False;
         begin
            case Query.Kind is
               when Query_Week =>
                  if Rec.Has_Date then
                     for D_Idx in 1 .. 7 loop
                        if Equal_Date (Rec.Date, Week_Days (D_Idx)) then
                           Matched := True;
                           exit;
                        end if;
                     end loop;
                  end if;

               when Query_Day =>
                  if Rec.Has_Date and then Equal_Date (Rec.Date, Query.Day_Date) then
                     Matched := True;
                  end if;

               when Query_Search =>
                  declare
                     Term : constant String :=
                       Query.Search_Text (1 .. Query.Search_Len);
                  begin
                     Matched := Matches_Search (Rec, Events.Element (I), Term);
                  end;

               when Query_Undated =>
                  Matched := not Rec.Has_Date;
            end case;

            if Matched then
               Match_Count := Match_Count + 1;
               Selected (Match_Count) := I;
            end if;
         end;
      end loop;

      --  4. Sort selected indices by record precedence
      if Match_Count > 1 then
         for I in 2 .. Match_Count loop
            declare
               Key_Idx : constant Positive := Selected (I);
               Key_Rec : constant Review_Record := All_Records (Key_Idx);
               J       : Natural := I - 1;
            begin
               while J > 0 and then Is_Earlier_In_Review (Key_Rec, All_Records (Selected (J))) loop
                  Selected (J + 1) := Selected (J);
                  J := J - 1;
               end loop;
               Selected (J + 1) := Key_Idx;
            end;
         end loop;
      end if;

      --  5. Print query header
      New_Line;
      case Query.Kind is
         when Query_Week =>
            Put_Line
              ("Week through " & Format_Iso_Date (Query.Ending_Date) &
               " (occurrence dates, not entry time)");
         when Query_Day =>
            Put_Line
              ("Day " & Format_Iso_Date (Query.Day_Date) &
               " (occurrence date, not entry time)");
         when Query_Search =>
            Put_Line
              ("Search all recorded Events, all dates + correction history: " &
               Query.Search_Text (1 .. Query.Search_Len));
         when Query_Undated =>
            Put_Line ("Current records with date unknown");
      end case;

      Put_Line ("Date unknown (current): " & Natural_Image (Undated_Cnt) & ".");

      --  6. Print week bar if applicable
      if Has_Week then
         for D_Idx in 1 .. 7 loop
            if D_Idx > 1 then
               Put ("  ");
            end if;
            declare
               D_Str   : constant Iso_Date_String := Format_Iso_Date (Week_Days (D_Idx));
               MM_DD   : constant String := D_Str (6 .. 10);
               Day_Cnt : Natural := 0;
            begin
               for I in 1 .. Total_Events loop
                  if All_Records (I).Has_Date
                    and then Equal_Date (All_Records (I).Date, Week_Days (D_Idx))
                  then
                     Day_Cnt := Day_Cnt + 1;
                  end if;
               end loop;
               Put (MM_DD & ":" & Natural_Image (Day_Cnt));
            end;
         end loop;
         New_Line;
      end if;

      --  7. Print count status
      if Match_Count = 0 then
         Put_Line ("No matches in this scope; this does not prove something was never recorded.");
      else
         declare
            Page_Len : constant Natural := Natural'Min (Page_Size, Match_Count);
         begin
            Put_Line
              ("Showing 1-" & Natural_Image (Page_Len) &
               " of " & Natural_Image (Match_Count) & " matches.");
         end;
      end if;

      --  8. Render page records
      declare
         Page_Len      : constant Natural := Natural'Min (Page_Size, Match_Count);
         Previous_Date : Iso_Date_String  := "0000-00-00";
         Has_Prev_Date : Boolean := False;
         Prev_Was_Null : Boolean := False;
      begin
         for I in 1 .. Page_Len loop
            declare
               Rec_Idx : constant Positive := Selected (I);
               Rec     : constant Review_Record := All_Records (Rec_Idx);
               Ev      : constant Event := Events.Element (Rec.Event_Idx);
               Sum_Buf : String (1 .. 1024);
               Sum_Len : Natural;
            begin
               if Rec.Has_Date then
                  declare
                     D_Str : constant Iso_Date_String := Format_Iso_Date (Rec.Date);
                  begin
                     if not Has_Prev_Date or else Previous_Date /= D_Str then
                        Put_Line (D_Str);
                        Previous_Date := D_Str;
                        Has_Prev_Date := True;
                        Prev_Was_Null := False;
                     end if;
                  end;
               else
                  if not Prev_Was_Null then
                     Put_Line ("date unknown");
                     Prev_Was_Null := True;
                     Has_Prev_Date := False;
                  end if;
               end if;

               Format_Summary (Rec, Ev, Sum_Buf, Sum_Len);
               Put_Line
                 ("  " & Natural_Image (I) & ". " & Sum_Buf (1 .. Sum_Len));
            end;
         end loop;
      end;

   end Execute_Review;

end HRA_N.Application.Review;
