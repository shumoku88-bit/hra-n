-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Reader
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File;
with HRA_N.Storage.Loam_Actual_Event_Block;
use HRA_N.Storage.Loam_Actual_Event_Block;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Loam_Actual_Reader is

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

   function Read_Loam_Actual_File
     (Path : String) return Loam_Actual_Result
   is
      Result : Loam_Actual_Result;
      File   : Ada.Text_IO.File_Type;
      Exact  : constant HRA_N.Storage.Exact_File.Read_Result :=
        HRA_N.Storage.Exact_File.Read_All (Path);

      Validity_Entries    : Validity_Entry_List;
      Description_Entries : Description_Entry_List;
      Metadata_Entries    : Metadata_List;
      Line_No             : Natural := 0;

      procedure Set_Error
        (At_Line : Natural;
         Message : String)
      is
         N : constant Natural :=
           Natural'Min (Message'Length, Result.Error_Reason'Length);
      begin
         Result.Success := False;
         Result.Error_Line := At_Line;
         Result.Error_Reason := [others => ' '];
         Result.Error_Len := N;
         if N > 0 then
            Result.Error_Reason (1 .. N) :=
              Message (Message'First .. Message'First + N - 1);
         end if;
      end Set_Error;

      function Fail
        (At_Line : Natural;
         Message : String) return Loam_Actual_Result
      is
      begin
         Set_Error (At_Line, Message);
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Result;
      end Fail;

   begin
      if not Exact.Success then
         return Fail (0, "cannot read LOAM Actual file");
      end if;

      declare
         Bytes : constant String := To_String (Exact.Content);
      begin
         if Bytes'Length = 0 then
            return Fail (0, "LOAM Actual document is empty");
         elsif Bytes (Bytes'Last) /= ASCII.LF then
            return Fail (0, "LOAM Actual document must end with newline");
         end if;
      end;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);

      if Ada.Text_IO.End_Of_File (File) then
         return Fail (0, "LOAM Actual document is empty");
      end if;

      Line_No := 1;
      declare
         First_Line : constant String := Ada.Text_IO.Get_Line (File);
      begin
         if First_Line /= Header then
            return Fail (Line_No, "unsupported LOAM Actual header");
         end if;
      end;

      while not Ada.Text_IO.End_Of_File (File) loop
         if Validity_Entries.Count = Max_Admitted_Actual_Events
           or else Metadata_Entries.Count = Metadata_Count'Last
         then
            return Fail
              (Line_No + 1, "HRA-N Actual bridge capacity exceeded");
         end if;

         declare
            Block_Start : constant Natural := Line_No + 1;
            First_Line  : constant String := Ada.Text_IO.Get_Line (File);
            Block       : Unbounded_String :=
              To_Unbounded_String (First_Line & ASCII.LF);
            Last_Line   : Unbounded_String :=
              To_Unbounded_String (First_Line);
         begin
            Line_No := Line_No + 1;

            if not Is_Row (First_Line, "TX") then
               return Fail (Line_No, "expected TX row");
            end if;

            while not Starts_With (To_String (Last_Line), "ENDTX") loop
               if Ada.Text_IO.End_Of_File (File) then
                  return Fail (Line_No, "missing final ENDTX");
               end if;

               declare
                  Line : constant String := Ada.Text_IO.Get_Line (File);
               begin
                  Line_No := Line_No + 1;
                  Append (Block, Line & ASCII.LF);
                  Last_Line := To_Unbounded_String (Line);
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
                     return Fail (Error_Line, "invalid Event block");
                  else
                     return Fail
                       (Error_Line,
                        Decoded.Error_Reason (1 .. Decoded.Error_Len));
                  end if;
               elsif Event_Exists (Result.Events, Id (Decoded.Value)) then
                  return Fail (Block_Start, "duplicate Event identity");
               elsif Decoded.Has_Description
                 and then
                   Description_Entries.Count = Description_Count_Type'Last
               then
                  return Fail
                    (Block_Start,
                     "HRA-N description bridge capacity exceeded");
               end if;

               Result.Events.Append (Decoded.Value);

               Validity_Entries.Count := Validity_Entries.Count + 1;
               Validity_Entries.Values (Validity_Entries.Count) :=
                 Decoded.Validity;

               if Decoded.Has_Description then
                  Description_Entries.Count :=
                    Description_Entries.Count + 1;
                  Description_Entries.Values
                    (Description_Entries.Count) := Decoded.Description;
               end if;

               Metadata_Entries.Count := Metadata_Entries.Count + 1;
               Metadata_Entries.Values (Metadata_Entries.Count) :=
                 Decoded.Metadata;
            end;
         end;
      end loop;

      if not Event_Ids_Are_Unique (Validity_Entries)
        or else not Event_Ids_Are_Unique (Description_Entries)
        or else not Metadata_Event_Ids_Are_Unique (Metadata_Entries)
      then
         return Fail
           (Line_No, "duplicate Event identity in decoded evidence");
      elsif not Replacement_References_Are_Closed (Metadata_Entries)
        or else not Replacements_Are_One_To_One (Metadata_Entries)
        or else not Replacements_Are_Acyclic (Metadata_Entries)
      then
         return Fail (Line_No, "invalid Event replacement topology");
      elsif not Reversal_References_Are_Closed (Metadata_Entries)
        or else not Reversals_Are_One_To_One (Metadata_Entries)
        or else not Reversals_Have_No_Chains (Metadata_Entries)
      then
         return Fail (Line_No, "invalid reversal topology");
      end if;

      for I in 1 .. Metadata_Entries.Count loop
         if Metadata_Entries.Values (I).Reverses.Present then
            declare
               Reversal_Event : Event;
               Target_Event   : Event;
               Have_Reversal  : Boolean;
               Have_Target    : Boolean;
            begin
               Find_Event
                 (Result.Events,
                  Metadata_Entries.Values (I).Event,
                  Reversal_Event,
                  Have_Reversal);
               Find_Event
                 (Result.Events,
                  Metadata_Entries.Values (I).Reverses.Value,
                  Target_Event,
                  Have_Target);
               if not Have_Reversal or else not Have_Target then
                  return Fail
                    (Line_No, "reversal endpoint is not readable");
               elsif not Exact_Physical_Inverse
                 (Target_Event, Reversal_Event)
               then
                  return Fail
                    (Line_No,
                     "reversal is not the exact physical inverse");
               end if;
            end;
         end if;
      end loop;

      --  The semantic image must still correspond to the exact byte snapshot
      --  observed before parsing. Re-read only after closing the Text_IO handle
      --  so an atomic authority replacement cannot silently change admission.
      Ada.Text_IO.Close (File);
      declare
         After : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Path);
      begin
         if not After.Success
           or else To_String (After.Content) /= To_String (Exact.Content)
         then
            return Fail
              (Line_No, "LOAM Actual changed while being read");
         end if;
      end;

      Result.Validities := Make_Validity_Memory (Validity_Entries);
      Result.Descriptions := Make_Description_Memory (Description_Entries);
      Result.Metadata := Make_Metadata_Memory (Metadata_Entries);
      Result.Success := True;
      return Result;

   exception
      when others =>
         return Fail
           (Line_No, "unexpected LOAM Actual reader failure");
   end Read_Loam_Actual_File;

end HRA_N.Storage.Loam_Actual_Reader;
