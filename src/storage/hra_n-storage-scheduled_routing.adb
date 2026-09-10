-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Scheduled_Routing
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Scheduled_Routing is

   Header : constant String := "LOAM-SCHEDULED-ROUTING" & ASCII.HT & "1";

   function Set_Error
     (Result : in out Read_Result; Line : Natural; Msg : String) return Read_Result is
   begin
      Result.Success := False;
      Result.Error_Line := Line;
      Result.Error_Len := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Error;

   function Valid_Token (Text : String) return Boolean is
     (Text'Length in 1 .. Max_Token_Length);

   function Parse_Date (Text : String; Value : out Date_Type) return Boolean is
   begin
      Value := (Year => 2026, Month => 1, Day => 1);
      if Text'Length /= 10
        or else Text (Text'First + 4) /= '-'
        or else Text (Text'First + 7) /= '-'
      then
         return False;
      end if;
      begin
         declare
            Y : constant Integer := Integer'Value (Text (Text'First .. Text'First + 3));
            M : constant Integer := Integer'Value (Text (Text'First + 5 .. Text'First + 6));
            D : constant Integer := Integer'Value (Text (Text'First + 8 .. Text'Last));
         begin
            if Y not in Year_Type or else M not in Month_Type or else D not in Day_Type
              or else not Is_Valid_Date (Y, M, D)
            then
               return False;
            end if;
            Value := Make_Date (Y, M, D);
            return True;
         end;
      exception
         when others => return False;
      end;
   end Parse_Date;

   function Read_File (Path : String) return Read_Result is
      Result : Read_Result;
      File : File_Type;
      Line_Number : Natural := 1;
      Fields : Field_Array;
      Count : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others => return Set_Error (Result, 0, "Cannot open scheduled routing file");
      end;
      if End_Of_File (File) or else Get_Line (File) /= Header then
         Close (File);
         return Set_Error (Result, 1, "Invalid scheduled routing header");
      end if;
      while not End_Of_File (File) loop
         Line_Number := Line_Number + 1;
         declare
            Line : constant String := Get_Line (File);
         begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, Count);
               if Count not in 6 .. 7 then
                  Close (File);
                  return Set_Error (Result, Line_Number, "Malformed ROUTE row");
               end if;
               declare
                  Marker : constant String := Line (Fields (1).First .. Fields (1).Last);
                  Sched : constant String := Line (Fields (2).First .. Fields (2).Last);
                  Locus : constant String := Line (Fields (3).First .. Fields (3).Last);
                  From : constant String := Line (Fields (4).First .. Fields (4).Last);
                  Date_Text : constant String := Line (Fields (5).First .. Fields (5).Last);
                  Mode : constant String := Line (Fields (6).First .. Fields (6).Last);
                  Date : Date_Type;
                  Managed : Boolean;
                  Purpose : Token_Text := (Length => 0, Value => [others => ' ']);
               begin
                  if Marker /= "ROUTE" or else From /= "FROM"
                    or else not Valid_Token (Sched) or else not Valid_Token (Locus)
                    or else not Parse_Date (Date_Text, Date)
                  then
                     Close (File);
                     return Set_Error (Result, Line_Number, "Invalid Scheduled route coordinate");
                  end if;
                  if Mode = "MANAGED" and then Count = 7 then
                     declare
                        P : constant String := Line (Fields (7).First .. Fields (7).Last);
                     begin
                        if not Valid_Token (P) then
                           Close (File);
                           return Set_Error (Result, Line_Number, "Invalid route purpose");
                        end if;
                        Managed := True;
                        Purpose := Make_Token (P);
                     end;
                  elsif Mode = "UNMANAGED" and then Count = 6 then
                     Managed := False;
                  else
                     Close (File);
                     return Set_Error (Result, Line_Number, "Invalid route target");
                  end if;
                  if Result.History.Count = Max_Scheduled_Routes then
                     Close (File);
                     return Set_Error (Result, Line_Number, "Scheduled routing memory full");
                  end if;
                  Result.History.Count := Result.History.Count + 1;
                  Result.History.Entries (Result.History.Count) :=
                    (Scheduled => (Token => Make_Token (Sched)),
                     Locus => (Token => Make_Token (Locus)), Effective_On => Date,
                     Managed => Managed, Purpose => Purpose);
                  if not Coordinates_Are_Unique (Result.History) then
                     Close (File);
                     return Set_Error (Result, Line_Number, "Duplicate route coordinate/date");
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (File);
      Result.Success := True;
      return Result;
   end Read_File;

   function Encode (History : Routing_History) return String is
      Text : Unbounded_String := To_Unbounded_String (Header & ASCII.LF);
   begin
      for I in 1 .. History.Count loop
         declare
            E : constant Scheduled_Route := History.Entries (I);
         begin
            Append (Text, "ROUTE" & ASCII.HT &
              E.Scheduled.Token.Value (1 .. E.Scheduled.Token.Length) & ASCII.HT &
              E.Locus.Token.Value (1 .. E.Locus.Token.Length) & ASCII.HT & "FROM" &
              ASCII.HT & Format_Iso_Date (E.Effective_On) & ASCII.HT);
            if E.Managed then
               Append (Text, "MANAGED" & ASCII.HT &
                 E.Purpose.Value (1 .. E.Purpose.Length));
            else
               Append (Text, "UNMANAGED");
            end if;
            Append (Text, ASCII.LF);
         end;
      end loop;
      return To_String (Text);
   end Encode;

end HRA_N.Storage.Scheduled_Routing;
