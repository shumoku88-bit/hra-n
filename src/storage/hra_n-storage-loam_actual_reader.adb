-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Reader
-------------------------------------------------------------------------------

with Ada.Exceptions;
with Ada.Finalization;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Event_Block;
use HRA_N.Storage.Loam_Actual_Event_Block;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Loam_Actual_Reader is

   --  The admitted result and its three bounded construction lists are large:
   --  each evidence family carries capacity for up to 1024 Events.  Keeping
   --  all four objects in one parser stack frame leaves very little headroom
   --  on platforms with smaller default thread stacks (notably macOS GUI
   --  entry points).  Own the construction workspace on the heap instead.
   --
   --  Workspace_Owner is limited-controlled so every normal/early/error
   --  return from the parser releases the allocation automatically.
   type Reader_Workspace is record
      Result              : Loam_Actual_Result;
      Validity_Entries    : Validity_Entry_List;
      Description_Entries : Description_Entry_List;
      Metadata_Entries    : Metadata_List;
   end record;

   type Reader_Workspace_Access is access Reader_Workspace;

   procedure Free_Workspace is new Ada.Unchecked_Deallocation
     (Object => Reader_Workspace,
      Name   => Reader_Workspace_Access);

   type Workspace_Owner is
     new Ada.Finalization.Limited_Controlled with record
        Data : Reader_Workspace_Access := null;
     end record;

   overriding procedure Finalize (Owner : in out Workspace_Owner) is
   begin
      if Owner.Data /= null then
         Free_Workspace (Owner.Data);
      end if;
   end Finalize;

   function Make_Failure
     (Status  : Actual_Read_Status;
      At_Line : Natural;
      Message : String) return Loam_Actual_Result
   is
      Result : Loam_Actual_Result (Success => False);
      N      : constant Natural :=
        Natural'Min (Message'Length, Result.Error_Reason'Length);
   begin
      Result.Status     := Status;
      Result.Error_Line := At_Line;
      Result.Error_Len  := N;
      if N > 0 then
         Result.Error_Reason (1 .. N) :=
           Message (Message'First .. Message'First + N - 1);
      end if;
      return Result;
   end Make_Failure;

   Header : constant String := "LOAM-NORMALIZED-ACTUAL" & ASCII.HT & "1";

   function Is_Row
     (Line : String;
      Kind : String) return Boolean
   is
   begin
      if Line'Length < Kind'Length then
         return False;
      elsif Line (Line'First .. Line'First + Kind'Length - 1) /= Kind then
         return False;
      elsif Line'Length = Kind'Length then
         return True;
      else
         return Line (Line'First + Kind'Length) = ASCII.HT;
      end if;
   end Is_Row;

   function Starts_With
     (Line   : String;
      Prefix : String) return Boolean
   is
   begin
      return Line'Length >= Prefix'Length
        and then
          Line (Line'First .. Line'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   Empty_Effects : constant Effect_List :=
     (Count => 0, Values => [others => Empty_Effect]);

   Empty_Event : constant Event :=
     Make_Event
       ((Token => (Length => 0, Value => [others => ' '])),
        Empty_Effects);

   procedure Find_Event
     (Events : in Event_Vectors.Vector;
      Ev_Id  : in Event_Id;
      Item   : out Event;
      Found  : out Boolean)
   is
   begin
      Item := Empty_Event;
      Found := False;
      for Ev of Events loop
         if Equal_Token (Id (Ev).Token, Ev_Id.Token) then
            Item := Ev;
            Found := True;
            return;
         end if;
      end loop;
   end Find_Event;

   function Event_Exists
     (Events : Event_Vectors.Vector;
      Ev_Id  : Event_Id) return Boolean
   is
      Item  : Event;
      Found : Boolean;
   begin
      Find_Event (Events, Ev_Id, Item, Found);
      return Found;
   end Event_Exists;

   function Exact_Physical_Inverse
     (Target   : Event;
      Reversal : Event) return Boolean
   is
      Matched : array (Effect_Index_Type) of Boolean := [others => False];
   begin
      if Effect_Count (Target) /= Effect_Count (Reversal) then
         return False;
      end if;

      for I in 1 .. Effect_Count (Target) loop
         declare
            T     : constant Effect := Effect_At (Target, Effect_Index_Type (I));
            Found : Boolean := False;
         begin
            for J in 1 .. Effect_Count (Reversal) loop
               if not Matched (Effect_Index_Type (J)) then
                  declare
                     R : constant Effect :=
                       Effect_At (Reversal, Effect_Index_Type (J));
                  begin
                     if Equal_Token (T.Locus.Token, R.Locus.Token)
                       and then Equal_Token (T.Measure.Token, R.Measure.Token)
                       and then R.Amount.Quanta = -T.Amount.Quanta
                     then
                        Matched (Effect_Index_Type (J)) := True;
                        Found := True;
                        exit;
                     end if;
                  end;
               end if;
            end loop;
            if not Found then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Exact_Physical_Inverse;

   procedure Next_Line
     (Content  : String;
      Position : in out Natural;
      Line     : out Unbounded_String;
      Success  : out Boolean)
   is
      LF : Natural := 0;
   begin
      Line := Null_Unbounded_String;
      Success := False;

      if Content'Length = 0
        or else Position < Content'First
        or else Position > Content'Last
      then
         return;
      end if;

      for I in Position .. Content'Last loop
         if Content (I) = ASCII.LF then
            LF := I;
            exit;
         end if;
      end loop;

      if LF = 0 then
         return;
      elsif LF > Position then
         Line := To_Unbounded_String (Content (Position .. LF - 1));
      end if;

      Position := LF + 1;
      Success := True;
   end Next_Line;

   function Read_Loam_Actual_Content
     (Content : String) return Loam_Actual_Result
   is
      Workspace : Workspace_Owner;
      Position  : Natural :=
        (if Content'Length = 0 then 0 else Content'First);
      Line_No   : Natural := 0;

      --  These names preserve the parser's existing logic while moving the
      --  backing storage out of this call frame.
      procedure Allocate_Workspace is
      begin
         Workspace.Data := new Reader_Workspace;
      end Allocate_Workspace;

      function Fail
        (Status  : Actual_Read_Status;
         At_Line : Natural;
         Message : String) return Loam_Actual_Result
      is
      begin
         return Make_Failure (Status, At_Line, Message);
      end Fail;

   begin
      Allocate_Workspace;

      if Content'Length = 0 then
         return Fail (Document_Empty, 0, "LOAM Actual document is empty");
      elsif Content (Content'Last) /= ASCII.LF then
         return Fail (Missing_Final_Newline, 0, "LOAM Actual document must end with newline");
      end if;

      declare
         First_Line : Unbounded_String;
         Have_Line  : Boolean;
      begin
         Next_Line (Content, Position, First_Line, Have_Line);
         if not Have_Line then
            return Fail (Document_Empty, 0, "LOAM Actual document is empty");
         end if;

         Line_No := 1;
         if To_String (First_Line) /= Header then
            return Fail (Unsupported_Header, Line_No, "unsupported LOAM Actual header");
         end if;
      end;

      while Position <= Content'Last loop
         if Workspace.Data.Validity_Entries.Count = Max_Admitted_Actual_Events
           or else Workspace.Data.Metadata_Entries.Count = Metadata_Count'Last
         then
            return Fail
              (Capacity_Exceeded, Line_No + 1, "HRA-N Actual bridge capacity exceeded");
         end if;

         declare
            Block_Start : constant Natural := Line_No + 1;
            First_Row   : Unbounded_String;
            Have_Line   : Boolean;
         begin
            Next_Line (Content, Position, First_Row, Have_Line);
            if not Have_Line then
               return Fail (Syntax_Error, Line_No + 1, "missing final ENDTX");
            end if;

            declare
               First_Line : constant String := To_String (First_Row);
               Block      : Unbounded_String :=
                 To_Unbounded_String (First_Line & ASCII.LF);
               Last_Line  : Unbounded_String := First_Row;
            begin
               Line_No := Line_No + 1;

               if not Is_Row (First_Line, "TX") then
                  return Fail (Syntax_Error, Line_No, "expected TX row");
               end if;

               while not Starts_With (To_String (Last_Line), "ENDTX") loop
                  if Position > Content'Last then
                     return Fail (Syntax_Error, Line_No, "missing final ENDTX");
                  end if;

                  declare
                     Line      : Unbounded_String;
                     Have_Next : Boolean;
                  begin
                     Next_Line (Content, Position, Line, Have_Next);
                     if not Have_Next then
                        return Fail (Syntax_Error, Line_No, "missing final ENDTX");
                     end if;
                     Line_No := Line_No + 1;
                     Append (Block, To_String (Line) & ASCII.LF);
                     Last_Line := Line;
                  end;
               end loop;

               declare
                  Decoded : constant Event_Block_Result :=
                    Decode_Event_Block (To_String (Block));
                  Error_Line : constant Natural :=
                    (if Decoded.Error_Line = 0 then
                        Block_Start
                     else
                        Block_Start + Decoded.Error_Line - 1);
               begin
                  if not Decoded.Success then
                     if Decoded.Error_Len = 0 then
                        return Fail (Syntax_Error, Error_Line, "invalid Event block");
                     else
                        return Fail
                          (Syntax_Error,
                           Error_Line,
                           Decoded.Error_Reason (1 .. Decoded.Error_Len));
                     end if;
                  elsif Event_Exists (Workspace.Data.Result.Events, Id (Decoded.Value)) then
                     return Fail (Duplicate_Event_Id, Block_Start, "duplicate Event identity");
                  elsif Decoded.Has_Description
                    and then
                      Workspace.Data.Description_Entries.Count = Description_Count_Type'Last
                  then
                     return Fail
                       (Capacity_Exceeded,
                        Block_Start,
                        "HRA-N description bridge capacity exceeded");
                  end if;

                  Workspace.Data.Result.Events.Append (Decoded.Value);

                  Workspace.Data.Validity_Entries.Count := Workspace.Data.Validity_Entries.Count + 1;
                  Workspace.Data.Validity_Entries.Values (Workspace.Data.Validity_Entries.Count) :=
                    Decoded.Validity;

                  if Decoded.Has_Description then
                     Workspace.Data.Description_Entries.Count :=
                       Workspace.Data.Description_Entries.Count + 1;
                     Workspace.Data.Description_Entries.Values
                       (Workspace.Data.Description_Entries.Count) := Decoded.Description;
                  end if;

                  Workspace.Data.Metadata_Entries.Count := Workspace.Data.Metadata_Entries.Count + 1;
                  Workspace.Data.Metadata_Entries.Values (Workspace.Data.Metadata_Entries.Count) :=
                    Decoded.Metadata;
               end;
            end;
         end;
      end loop;

      if not Event_Ids_Are_Unique (Workspace.Data.Validity_Entries)
        or else not Event_Ids_Are_Unique (Workspace.Data.Description_Entries)
        or else not Metadata_Event_Ids_Are_Unique (Workspace.Data.Metadata_Entries)
      then
         return Fail
           (Duplicate_Event_Id,
            Line_No, "duplicate Event identity in decoded evidence");
      elsif not Replacement_References_Are_Closed (Workspace.Data.Metadata_Entries)
        or else not Replacements_Are_One_To_One (Workspace.Data.Metadata_Entries)
        or else not Replacements_Are_Acyclic (Workspace.Data.Metadata_Entries)
      then
         return Fail (Invalid_Topology, Line_No, "invalid Event replacement topology");
      elsif not Reversal_References_Are_Closed (Workspace.Data.Metadata_Entries)
        or else not Reversals_Are_One_To_One (Workspace.Data.Metadata_Entries)
        or else not Reversals_Have_No_Chains (Workspace.Data.Metadata_Entries)
      then
         return Fail (Invalid_Topology, Line_No, "invalid reversal topology");
      end if;

      for I in 1 .. Workspace.Data.Metadata_Entries.Count loop
         if Workspace.Data.Metadata_Entries.Values (I).Reverses.Present then
            declare
               Reversal_Event : Event;
               Target_Event   : Event;
               Have_Reversal  : Boolean;
               Have_Target    : Boolean;
            begin
               Find_Event
                 (Workspace.Data.Result.Events,
                  Workspace.Data.Metadata_Entries.Values (I).Event,
                  Reversal_Event,
                  Have_Reversal);
               Find_Event
                 (Workspace.Data.Result.Events,
                  Workspace.Data.Metadata_Entries.Values (I).Reverses.Value,
                  Target_Event,
                  Have_Target);
               if not Have_Reversal or else not Have_Target then
                  return Fail
                    (Invalid_Topology,
                     Line_No, "reversal endpoint is not readable");
               elsif not Exact_Physical_Inverse
                 (Target_Event, Reversal_Event)
               then
                  return Fail
                    (Invalid_Topology,
                     Line_No,
                     "reversal is not the exact physical inverse");
               end if;
            end;
         end if;
      end loop;

      Workspace.Data.Result.Validities := Make_Validity_Memory (Workspace.Data.Validity_Entries);
      Workspace.Data.Result.Descriptions := Make_Description_Memory (Workspace.Data.Description_Entries);
      Workspace.Data.Result.Metadata := Make_Metadata_Memory (Workspace.Data.Metadata_Entries);
      return Workspace.Data.Result;

   exception
      when E : others =>
         return Fail
           (IO_Error,
            Line_No,
            "unexpected LOAM Actual reader failure: "
            & Ada.Exceptions.Exception_Name (E)
            & (if Ada.Exceptions.Exception_Message (E)'Length = 0
               then ""
               else ": " & Ada.Exceptions.Exception_Message (E)));
   end Read_Loam_Actual_Content;

   function Read_Loam_Actual_File
     (Path : String) return Loam_Actual_Result
   is
      Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
        HRA_N.Storage.Exact_File.Read_All (Path);
   begin
      if not Exact.Success then
         return Make_Failure
           (IO_Error, 0, "cannot read LOAM Actual file");
      end if;

      return Read_Loam_Actual_Content (To_String (Exact.Content));
   exception
      when E : others =>
         return Make_Failure
           (IO_Error, 0,
            "unexpected LOAM Actual file-reader failure: "
            & Ada.Exceptions.Exception_Name (E)
            & (if Ada.Exceptions.Exception_Message (E)'Length = 0
               then ""
               else ": " & Ada.Exceptions.Exception_Message (E)));
   end Read_Loam_Actual_File;

   function Format_Error (Result : Loam_Actual_Result) return String is
   begin
      if Result.Success then
         return "";
      elsif Result.Error_Len > 0 then
         return Result.Error_Reason (1 .. Result.Error_Len);
      else
         case Result.Status is
            when Document_Empty        => return "LOAM Actual document is empty";
            when Missing_Final_Newline => return "LOAM Actual document must end with newline";
            when Unsupported_Header    => return "unsupported LOAM Actual header";
            when Syntax_Error          => return "syntax error in LOAM Actual document";
            when Duplicate_Event_Id    => return "duplicate Event identity";
            when Capacity_Exceeded     => return "exceeded maximum admitted Events";
            when Invalid_Topology      => return "invalid Event topology";
            when IO_Error              => return "I/O error reading LOAM Actual document";
         end case;
      end if;
   end Format_Error;

end HRA_N.Storage.Loam_Actual_Reader;
