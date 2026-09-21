-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Byte_Spans
-------------------------------------------------------------------------------

package body HRA_N.Storage.Loam_Actual_Byte_Spans is

   Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";

   function Span_Is_Valid
     (Content : String;
      Span    : Event_Byte_Span) return Boolean
   is
   begin
      return Content'Length > 0
        and then Span.First_Byte >= 1
        and then Span.Last_Byte >= Span.First_Byte
        and then Span.Last_Byte <= Content'Length;
   end Span_Is_Valid;

   function Slice_Event_Block
     (Content : String;
      Span    : Event_Byte_Span) return String
   is
      First : constant Integer :=
        Content'First + Integer (Span.First_Byte) - 1;
      Last  : constant Integer :=
        Content'First + Integer (Span.Last_Byte) - 1;
   begin
      return Content (First .. Last);
   end Slice_Event_Block;

   function Locate_Event_Byte_Spans (Content : String) return Locate_Result
   is
      Result       : Locate_Result;
      Header_LF    : Natural := 0;
      Position     : Natural := 0;
      In_Tx        : Boolean := False;
      Current_Key  : Event_Id :=
        (Token => (Length => 0, Value => [others => ' ']));
      Current_First : Byte_Offset := 0;

      function Is_Exact_Line
        (Start    : Natural;
         LF_Index : Natural;
         Text     : String) return Boolean
      is
      begin
         return LF_Index >= Start
           and then LF_Index - Start = Text'Length
           and then
             (if Text'Length = 0 then True
              else Content (Start .. LF_Index - 1) = Text);
      end Is_Exact_Line;

      function Is_TX_Line
        (Start    : Natural;
         LF_Index : Natural) return Boolean
      is
      begin
         return LF_Index >= Start + 3
           and then Content (Start) = 'T'
           and then Content (Start + 1) = 'X'
           and then Content (Start + 2) = ASCII.HT;
      end Is_TX_Line;

      procedure Fail is
      begin
         Result.Success := False;
         Result.Count := 0;
      end Fail;

   begin
      if Content'Length = 0 then
         return Result;
      end if;

      for I in Content'Range loop
         if Content (I) = ASCII.LF then
            Header_LF := I;
            exit;
         end if;
      end loop;

      if Header_LF = 0
        or else Header_LF = Content'First
        or else Content (Content'First .. Header_LF - 1) /= Header
      then
         return Result;
      end if;

      Position := Header_LF + 1;

      while Position <= Content'Last loop
         declare
            Line_LF : Natural := 0;
         begin
            for I in Position .. Content'Last loop
               if Content (I) = ASCII.LF then
                  Line_LF := I;
                  exit;
               end if;
            end loop;

            if Line_LF = 0 then
               Fail;
               return Result;
            end if;

            if not In_Tx then
               if not Is_TX_Line (Position, Line_LF) then
                  Fail;
                  return Result;
               end if;

               declare
                  Event_Start : constant Natural := Position + 3;
                  Second_Tab  : Natural := 0;
               begin
                  for I in Event_Start .. Line_LF - 1 loop
                     if Content (I) = ASCII.HT then
                        Second_Tab := I;
                        exit;
                     end if;
                  end loop;

                  if Second_Tab = 0
                    or else Second_Tab = Event_Start
                    or else Second_Tab - Event_Start > Max_Token_Length
                  then
                     Fail;
                     return Result;
                  end if;

                  Current_Key :=
                    (Token =>
                       Make_Token (Content (Event_Start .. Second_Tab - 1)));
                  Current_First :=
                    Byte_Offset (Position - Content'First + 1);
                  In_Tx := True;
               end;

            elsif Is_Exact_Line (Position, Line_LF, "ENDTX") then
               if Result.Count = Max_Located_Events then
                  Fail;
                  return Result;
               end if;

               Result.Count := Result.Count + 1;
               Result.Spans (Result.Count) :=
                 (Key        => Current_Key,
                  First_Byte => Current_First,
                  Last_Byte  =>
                    Byte_Offset (Line_LF - Content'First + 1));
               In_Tx := False;
               Current_First := 0;

            elsif Is_TX_Line (Position, Line_LF) then
               Fail;
               return Result;
            end if;

            Position := Line_LF + 1;
         end;
      end loop;

      if In_Tx then
         Fail;
         return Result;
      end if;

      Result.Success := True;
      return Result;
   end Locate_Event_Byte_Spans;

end HRA_N.Storage.Loam_Actual_Byte_Spans;
