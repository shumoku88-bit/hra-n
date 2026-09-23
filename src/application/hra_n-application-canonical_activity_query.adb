with Ada.Directories;
with Ada.Unchecked_Deallocation;
with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;

package body HRA_N.Application.Canonical_Activity_Query is

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Snapshot_Data,
      Name   => Snapshot_Data_Access);

   overriding procedure Adjust (Source : in out Browser_Snapshot) is
   begin
      if Source.Data /= null then
         if Source.Data.References = Positive'Last then
            raise Program_Error with "canonical browser snapshot reference overflow";
         end if;
         Source.Data.References := Source.Data.References + 1;
      end if;
   end Adjust;

   overriding procedure Finalize (Source : in out Browser_Snapshot) is
      Data : Snapshot_Data_Access := Source.Data;
   begin
      Source.Data := null;

      if Data = null then
         return;
      elsif Data.References = 1 then
         Free (Data);
      else
         Data.References := Data.References - 1;
      end if;
   end Finalize;

   function Ready (Source : Browser_Snapshot) return Boolean is
     (Source.Data /= null and then Source.Data.Is_Ready);

   function Diagnostic (Source : Browser_Snapshot) return String is
     (if Source.Data = null or else Source.Data.Msg_Len = 0
      then ""
      else Source.Data.Message (1 .. Source.Data.Msg_Len));

   function Balance
     (Source : Browser_Snapshot)
      return HRA_N.Application.Canonical_Balance_Query.Balance_View
   is
      Result : HRA_N.Application.Canonical_Balance_Query.Balance_View;
   begin
      if Source.Data = null then
         declare
            Message : constant String := "canonical browser snapshot is absent";
         begin
            Result.Diagnostic_Len := Message'Length;
            Result.Diagnostic (1 .. Message'Length) := Message;
         end;
         return Result;
      end if;

      return Source.Data.Balances;
   end Balance;

   procedure Set_Message
     (Data    : in out Snapshot_Data;
      Message : String)
   is
      Len : constant Natural :=
        Natural'Min (Message'Length, Data.Message'Length);
   begin
      Data.Message := [others => ' '];
      Data.Msg_Len := Len;
      if Len > 0 then
         Data.Message (1 .. Len) :=
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

   procedure Set_Detail_Diagnostic
     (View    : in out Event_Detail_View;
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
   end Set_Detail_Diagnostic;

   function Open (Root_Path : String) return Browser_Snapshot is
      Source : Browser_Snapshot;
   begin
      Source.Data := new Snapshot_Data;

      if Root_Path'Length = 0 then
         Set_Message (Source.Data.all, "canonical data root must not be empty");
         return Source;
      end if;

      Source.Data.Actual :=
        HRA_N.Storage.Loam_Actual_Reader.Read_Loam_Actual_File
          (Ada.Directories.Compose (Root_Path, "actual.loam"));

      if not Source.Data.Actual.Success then
         if Source.Data.Actual.Error_Len > 0 then
            Set_Message
              (Source.Data.all,
               "cannot admit canonical actual.loam: "
               & Source.Data.Actual.Error_Reason
                   (1 .. Source.Data.Actual.Error_Len));
         else
            Set_Message
              (Source.Data.all, "cannot admit canonical actual.loam");
         end if;
         return Source;
      end if;

      Source.Data.Balances :=
        HRA_N.Application.Canonical_Balance_Query.Project
          (Source.Data.Actual);

      if not Source.Data.Balances.Success then
         if Source.Data.Balances.Diagnostic_Len > 0 then
            Set_Message
              (Source.Data.all,
               Source.Data.Balances.Diagnostic
                 (1 .. Source.Data.Balances.Diagnostic_Len));
         else
            Set_Message
              (Source.Data.all, "canonical balance projection failed");
         end if;
         return Source;
      end if;

      Source.Data.Is_Ready := True;
      Source.Data.Msg_Len := 0;
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
      if Source.Data = null or else not Source.Data.Is_Ready then
         Set_Diagnostic
           (Result,
            (if Source.Data /= null and then Source.Data.Msg_Len > 0
             then Source.Data.Message (1 .. Source.Data.Msg_Len)
             else "canonical browser snapshot is not ready"));
         return Result;
      end if;

      for Position in 1 .. Natural (Source.Data.Actual.Events.Length) loop
         declare
            Ev : constant Event :=
              Source.Data.Actual.Events.Element (Positive (Position));
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
                 (Source.Data.Actual.Metadata,
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
                    (Source.Data.Actual.Validities,
                     Id (Ev),
                     Occurred,
                     Have_Date);
                  Find_Description
                    (Source.Data.Actual.Descriptions,
                     Id (Ev),
                     Desc,
                     Have_Desc);
                  Find_Metadata
                    (Source.Data.Actual.Metadata,
                     Id (Ev),
                     Metadata,
                     Have_Metadata);
                  Find_Reverser
                    (Source.Data.Actual.Metadata,
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

   function Event_Detail_For
     (Source : Browser_Snapshot;
      Target : Event_Id) return Event_Detail_View
   is
      Result : Event_Detail_View;
   begin
      if Source.Data = null or else not Source.Data.Is_Ready then
         Set_Detail_Diagnostic
           (Result,
            (if Source.Data /= null and then Source.Data.Msg_Len > 0
             then Source.Data.Message (1 .. Source.Data.Msg_Len)
             else "canonical browser snapshot is not ready"));
         return Result;
      end if;

      for Position in 1 .. Natural (Source.Data.Actual.Events.Length) loop
         declare
            Ev : constant Event :=
              Source.Data.Actual.Events.Element (Positive (Position));
         begin
            if Equal_Token (Id (Ev).Token, Target.Token) then
               declare
                  Occurred       : Date_Type;
                  Have_Date      : Boolean;
                  Desc           : Description_Text;
                  Have_Desc      : Boolean;
                  Metadata       : Transaction_Metadata_Entry;
                  Have_Metadata  : Boolean;
                  Successor      : Event_Id;
                  Is_Superseded  : Boolean := False;
                  Reverser       : Event_Id;
                  Have_Reverser  : Boolean := False;
               begin
                  Find_Occurrence_Date
                    (Source.Data.Actual.Validities,
                     Id (Ev),
                     Occurred,
                     Have_Date);
                  Find_Description
                    (Source.Data.Actual.Descriptions,
                     Id (Ev),
                     Desc,
                     Have_Desc);
                  Find_Metadata
                    (Source.Data.Actual.Metadata,
                     Id (Ev),
                     Metadata,
                     Have_Metadata);
                  Find_Successor
                    (Source.Data.Actual.Metadata,
                     Id (Ev),
                     Successor,
                     Is_Superseded);
                  Find_Reverser
                    (Source.Data.Actual.Metadata,
                     Id (Ev),
                     Reverser,
                     Have_Reverser);

                  if not Have_Date then
                     Set_Detail_Diagnostic
                       (Result,
                        "canonical Event detail is missing validity evidence");
                     return Result;
                  elsif not Have_Metadata then
                     Set_Detail_Diagnostic
                       (Result,
                        "canonical Event detail is missing metadata evidence");
                     return Result;
                  end if;

                  Result.Event := Id (Ev);
                  Result.Valid_On := Occurred;
                  Result.Has_Description := Have_Desc;
                  Result.Description := Desc;
                  Result.Is_Superseded := Is_Superseded;
                  Result.Successor := Successor;
                  Result.Is_Replacement := Metadata.Replaces.Present;
                  Result.Replaces := Metadata.Replaces.Value;
                  Result.Is_Reversal := Metadata.Reverses.Present;
                  Result.Reverses := Metadata.Reverses.Value;
                  Result.Has_Reverser := Have_Reverser;
                  Result.Reversed_By := Reverser;
                  Result.Effect_Count :=
                    Detail_Effect_Count (Effect_Count (Ev));

                  for I in 1 .. Effect_Count (Ev) loop
                     declare
                        Item : constant Effect := Effect_At (Ev, I);
                     begin
                        Result.Effects (Detail_Effect_Index (I)) :=
                          (Has_Key => Item.Key.Present,
                           Key     => Item.Key.Value,
                           Locus   => Item.Locus,
                           Measure => Item.Measure,
                           Amount  => Long_Long_Integer (Item.Amount.Quanta));
                     end;
                  end loop;

                  Result.Success := True;
                  Result.Diagnostic_Len := 0;
                  return Result;
               end;
            end if;
         end;
      end loop;

      Set_Detail_Diagnostic
        (Result, "canonical Event identity was not found in snapshot");
      return Result;
   end Event_Detail_For;

end HRA_N.Application.Canonical_Activity_Query;
