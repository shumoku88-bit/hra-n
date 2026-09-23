with Ada.Directories;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;

package body HRA_N.Application.Canonical_Activity_Query is

   function Ready (Source : Browser_Snapshot) return Boolean is
     (Source.Is_Ready);

   function Diagnostic (Source : Browser_Snapshot) return String is
     (if Source.Msg_Len = 0
      then ""
      else Source.Message (1 .. Source.Msg_Len));

   function Balance
     (Source : Browser_Snapshot)
      return HRA_N.Application.Canonical_Balance_Query.Balance_View is
     (Source.Balances);

   procedure Set_Message
     (Source  : in out Browser_Snapshot;
      Message : String)
   is
      Len : constant Natural :=
        Natural'Min (Message'Length, Source.Message'Length);
   begin
      Source.Message := [others => ' '];
      Source.Msg_Len := Len;
      if Len > 0 then
         Source.Message (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end if;
   end Set_Message;

   procedure Set_Diagnostic
     (View    : in out Activity_View;
      Message : String)
   is
      Len : constant Natural :=
        Natural'Min (Message'Length, View.Diagnostic'Length);
   begin
      View.Success := False;
      View.Diagnostic := [others => ' '];
      View.Diagnostic_Len := Len;
      if Len > 0 then
         View.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end if;
   end Set_Diagnostic;

   function Open (Root_Path : String) return Browser_Snapshot is
      Source : Browser_Snapshot;
   begin
      if Root_Path'Length = 0 then
         Set_Message (Source, "canonical data root must not be empty");
         return Source;
      end if;

      Source.Actual :=
        HRA_N.Storage.Loam_Actual_Reader.Read_Loam_Actual_File
          (Ada.Directories.Compose (Root_Path, "actual.loam"));

      if not Source.Actual.Success then
         if Source.Actual.Error_Len > 0 then
            Set_Message
              (Source,
               "cannot admit canonical actual.loam: "
               & Source.Actual.Error_Reason
                   (1 .. Source.Actual.Error_Len));
         else
            Set_Message (Source, "cannot admit canonical actual.loam");
         end if;
         return Source;
      end if;

      Source.Balances :=
        HRA_N.Application.Canonical_Balance_Query.Project (Source.Actual);

      if not Source.Balances.Success then
         if Source.Balances.Diagnostic_Len > 0 then
            Set_Message
              (Source,
               Source.Balances.Diagnostic
                 (1 .. Source.Balances.Diagnostic_Len));
         else
            Set_Message
              (Source, "canonical balance projection failed");
         end if;
         return Source;
      end if;

      Source.Is_Ready := True;
      Source.Msg_Len := 0;
      return Source;
   end Open;

   function Row_Before (Left, Right : Activity_Row) return Boolean is
   begin
      if Date_Greater (Left.Valid_On, Right.Valid_On) then
         return True;
      elsif Date_Greater (Right.Valid_On, Left.Valid_On) then
         return False;
      end if;

      return Token_Less (Left.Event.Token, Right.Event.Token);
   end Row_Before;

   function Activity_For
     (Source  : Browser_Snapshot;
      Locus   : Locus_Id;
      Measure : Measure_Id) return Activity_View
   is
      Result : Activity_View;
   begin
      if not Source.Is_Ready then
         Set_Diagnostic
           (Result,
            (if Source.Msg_Len > 0
             then Source.Message (1 .. Source.Msg_Len)
             else "canonical browser snapshot is not ready"));
         return Result;
      end if;

      for Position in 1 .. Natural (Source.Actual.Events.Length) loop
         declare
            Ev : constant Event :=
              Source.Actual.Events.Element (Positive (Position));
            Net           : Long_Long_Integer := 0;
            Postings      : Natural := 0;
            Touched       : Boolean := False;
            Successor     : Event_Id;
            Is_Superseded : Boolean := False;
         begin
            for I in 1 .. Effect_Count (Ev) loop
               declare
                  Item : constant Effect := Effect_At (Ev, I);
               begin
                  if Equal_Token (Item.Locus.Token, Locus.Token)
                    and then Equal_Token
                      (Item.Measure.Token, Measure.Token)
                  then
                     Touched := True;
                     Postings := Postings + 1;
                     Net := Net + Long_Long_Integer (Item.Amount.Quanta);
                  end if;
               end;
            end loop;

            if Touched then
               if Result.Count = Max_Activity_Rows then
                  Set_Diagnostic
                    (Result, "canonical coordinate activity limit exceeded");
                  return Result;
               end if;

               Find_Successor
                 (Source.Actual.Metadata,
                  Id (Ev),
                  Successor,
                  Is_Superseded);

               declare
                  Occurred : Date_Type;
                  Have_Date : Boolean;
                  Desc      : Description_Text;
                  Have_Desc : Boolean;
                  Metadata  : Transaction_Metadata_Entry;
                  Have_Metadata : Boolean;
                  Reverser  : Event_Id;
                  Have_Reverser : Boolean;
               begin
                  Find_Occurrence_Date
                    (Source.Actual.Validities,
                     Id (Ev),
                     Occurred,
                     Have_Date);
                  Find_Description
                    (Source.Actual.Descriptions,
                     Id (Ev),
                     Desc,
                     Have_Desc);
                  Find_Metadata
                    (Source.Actual.Metadata,
                     Id (Ev),
                     Metadata,
                     Have_Metadata);
                  Find_Reverser
                    (Source.Actual.Metadata,
                     Id (Ev),
                     Reverser,
                     Have_Reverser);

                  if not Have_Date then
                     Set_Diagnostic
                       (Result,
                        "canonical Event activity is missing validity evidence");
                     return Result;
                  elsif not Have_Metadata then
                     Set_Diagnostic
                       (Result,
                        "canonical Event activity is missing metadata evidence");
                     return Result;
                  end if;

                  Result.Count := Result.Count + 1;
                  Result.Rows (Result.Count) :=
                    (Event             => Id (Ev),
                     Valid_On          => Occurred,
                     Has_Description   => Have_Desc,
                     Description       => Desc,
                     Net_Change        => Net,
                     Posting_Count     => Postings,
                     Is_Superseded     => Is_Superseded,
                     Successor         => Successor,
                     Is_Replacement    => Metadata.Replaces.Present,
                     Replaces          => Metadata.Replaces.Value,
                     Is_Reversal       => Metadata.Reverses.Present,
                     Reverses          => Metadata.Reverses.Value,
                     Has_Reverser      => Have_Reverser,
                     Reversed_By       => Reverser);

                  if Is_Superseded then
                     Result.Superseded_Count :=
                       Result.Superseded_Count + 1;
                  else
                     Result.Active_Count := Result.Active_Count + 1;
                  end if;
               end;
            end if;
         end;
      end loop;

      for I in 2 .. Result.Count loop
         declare
            Key : constant Activity_Row := Result.Rows (I);
            J   : Natural := I - 1;
         begin
            while J > 0 and then Row_Before (Key, Result.Rows (J)) loop
               Result.Rows (J + 1) := Result.Rows (J);
               J := J - 1;
            end loop;
            Result.Rows (J + 1) := Key;
         end;
      end loop;

      Result.Success := True;
      Result.Diagnostic_Len := 0;
      return Result;
   end Activity_For;

end HRA_N.Application.Canonical_Activity_Query;
