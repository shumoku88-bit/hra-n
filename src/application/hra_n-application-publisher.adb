-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Publisher
-------------------------------------------------------------------------------

with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with GNAT.SHA256;

with HRA_N.Storage.Sync;            use HRA_N.Storage.Sync;
with HRA_N.Storage.Atomic_Writer;   use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Manifest;        use HRA_N.Storage.Manifest;
with HRA_N.Storage.Locus_Reader;    use HRA_N.Storage.Locus_Reader;
with HRA_N.Core.Admission;          use HRA_N.Core.Admission;
with HRA_N.Core.Event;              use HRA_N.Core.Event;
with HRA_N.Storage.Event_Reader;    use HRA_N.Storage.Event_Reader;

package body HRA_N.Application.Publisher is

   function Set_Error
     (Result : in out Publish_Result;
      Msg    : String) return Publish_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Read_Entire_File (Path : String) return Unbounded_String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;

      File   : SIO.File_Type;
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      if not Ada.Directories.Exists (Path) then
         return Null_Unbounded_String;
      end if;

      SIO.Open (File, SIO.In_File, Path);
      declare
         Size   : constant SIO.Count := SIO.Size (File);
         Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last   : Ada.Streams.Stream_Element_Offset;
      begin
         if Size > 0 then
            SIO.Read (File, Buffer, Last);
            declare
               Str : String (1 .. Natural (Last));
               for Str'Address use Buffer'Address;
            begin
               Result := To_Unbounded_String (Str);
            end;
         end if;
      end;
      SIO.Close (File);
      return Result;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         return Null_Unbounded_String;
   end Read_Entire_File;

   function Compute_Sha256_Hex (Content : String) return String is
      Ctx : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      Hex : constant String :=
        "0123456789abcdef";
   begin
      GNAT.SHA256.Update (Ctx, Content);
      declare
         Digest : constant GNAT.SHA256.Binary_Message_Digest :=
           GNAT.SHA256.Digest (Ctx);
         Result : String (1 .. 64);
         Pos    : Positive := 1;
      begin
         for I in Digest'Range loop
            declare
               B : constant Natural := Natural (Digest (I));
            begin
               Result (Pos)     := Hex ((B / 16) + 1);
               Result (Pos + 1) := Hex ((B mod 16) + 1);
               Pos := Pos + 2;
            end;
         end loop;
         return Result;
      end;
   end Compute_Sha256_Hex;

   function Escape_Text (S : String) return String is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      for I in S'Range loop
         case S (I) is
            when '\' =>
               Append (Result, "\\");
            when ASCII.LF =>
               Append (Result, "\n");
            when ASCII.CR =>
               Append (Result, "\r");
            when ASCII.HT =>
               Append (Result, "\t");
            when others =>
               Append (Result, S (I));
         end case;
      end loop;
      return To_String (Result);
   end Escape_Text;

   function Extract_Max_Record_Number (Event_Content : String) return Natural is
      Max_Num : Natural := 0;
      Pos     : Positive := Event_Content'First;
      Prefix  : constant String := "EVENT" & ASCII.HT & "record-";
   begin
      while Pos <= Event_Content'Last - Prefix'Length + 1 loop
         if Event_Content (Pos .. Pos + Prefix'Length - 1) = Prefix then
            Pos := Pos + Prefix'Length;
            declare
               Start_Dig : constant Positive := Pos;
            begin
               while Pos <= Event_Content'Last and then Event_Content (Pos) in '0' .. '9' loop
                  Pos := Pos + 1;
               end loop;
               if Pos > Start_Dig then
                  declare
                     Num : constant Natural :=
                       Natural'Value (Event_Content (Start_Dig .. Pos - 1));
                  begin
                     if Num > Max_Num then
                        Max_Num := Num;
                     end if;
                  end;
               end if;
            end;
         else
            Pos := Pos + 1;
         end if;
      end loop;
      return Max_Num;
   end Extract_Max_Record_Number;

   function Natural_Image (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Natural_Image;

   function Quanta_Image (Q : Quanta_Type) return String is
      Img : constant String := Quanta_Type'Image (Q);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Quanta_Image;

   function Commit_Authority_Update
     (Authority_Dir  : String;
      Manifest_Path  : String;
      Man_Res        : Read_Manifest_Result;
      Curr_Content   : Unbounded_String;
      New_Event_Text : String;
      New_Val_Text   : String;
      New_Desc_Text  : String;
      Err_Buf        : in out String;
      Err_Len        : in out Natural) return Boolean
   is
      --  Compute cryptographic SHA-256 for each new object
      New_Event_Sha : constant String := Compute_Sha256_Hex (New_Event_Text);
      New_Val_Sha   : constant String := Compute_Sha256_Hex (New_Val_Text);
      New_Desc_Sha  : constant String := Compute_Sha256_Hex (New_Desc_Text);

      --  Target paths
      New_Event_Path : constant String :=
        Authority_Dir & "/objects/Event/" & New_Event_Sha & ".loam";
      New_Val_Path   : constant String :=
        Authority_Dir & "/objects/ActualValidity/" & New_Val_Sha & ".loam";
      New_Desc_Path  : constant String :=
        Authority_Dir & "/objects/EventDescription/" & New_Desc_Sha & ".loam";

      --  Old CURRENT sha and recovery path
      Old_Manifest_Sha  : constant String := Compute_Sha256_Hex (To_String (Curr_Content));
      Recovery_Man_Path : constant String :=
        Authority_Dir & "/recovery/manifests/" & Old_Manifest_Sha & ".loam";

      --  New CURRENT text
      New_Manifest_Text : constant String :=
        "LOAM-MOVEMENT-MANIFEST" & ASCII.HT & "2" & ASCII.LF &
        "Event" & ASCII.HT & "objects/Event/" & New_Event_Sha & ".loam" &
        ASCII.HT & New_Event_Sha & ASCII.LF &
        "ActualValidity" & ASCII.HT & "objects/ActualValidity/" & New_Val_Sha & ".loam" &
        ASCII.HT & New_Val_Sha & ASCII.LF &
        "EventDescription" & ASCII.HT & "objects/EventDescription/" & New_Desc_Sha & ".loam" &
        ASCII.HT & New_Desc_Sha & ASCII.LF &
        "RelationUnit" & ASCII.HT &
        Man_Res.Manifest (Family_Relation_Unit).Rel_Path
          (1 .. Man_Res.Manifest (Family_Relation_Unit).Path_Len) &
        ASCII.HT &
        Man_Res.Manifest (Family_Relation_Unit).Digest (1 .. 64) & ASCII.LF &
        "RelationDischarge" & ASCII.HT &
        Man_Res.Manifest (Family_Relation_Discharge).Rel_Path
          (1 .. Man_Res.Manifest (Family_Relation_Discharge).Path_Len) &
        ASCII.HT &
        Man_Res.Manifest (Family_Relation_Discharge).Digest (1 .. 64) & ASCII.LF &
        "LocusAdmission" & ASCII.HT &
        Man_Res.Manifest (Family_Locus_Admission).Rel_Path
          (1 .. Man_Res.Manifest (Family_Locus_Admission).Path_Len) &
        ASCII.HT &
        Man_Res.Manifest (Family_Locus_Admission).Digest (1 .. 64) & ASCII.LF;
   begin
      --  1. Write new content-addressed immutable objects
      if not Write_File_Atomically (New_Event_Path, New_Event_Text, Err_Buf, Err_Len) then
         return False;
      end if;

      if not Write_File_Atomically (New_Val_Path, New_Val_Text, Err_Buf, Err_Len) then
         return False;
      end if;

      if not Write_File_Atomically (New_Desc_Path, New_Desc_Text, Err_Buf, Err_Len) then
         return False;
      end if;

      --  2. Retain old CURRENT manifest as immutable recovery candidate
      if not Ada.Directories.Exists (Recovery_Man_Path) then
         if not Write_File_Atomically
           (Recovery_Man_Path, To_String (Curr_Content), Err_Buf, Err_Len)
         then
            return False;
         end if;
      end if;

      --  3. Atomically replace CURRENT manifest
      if not Write_File_Atomically (Manifest_Path, New_Manifest_Text, Err_Buf, Err_Len) then
         return False;
      end if;

      return True;
   end Commit_Authority_Update;

   function Publish_Movement
     (Authority_Dir : String;
      From_Locus    : String;
      To_Locus      : String;
      Amount        : Quanta_Type;
      Valid_On      : Date_Type;
      Description   : String := "";
      Explicit_Id   : String := "") return Publish_Result
   is
      Result    : Publish_Result;
      Lock_Path : constant String := Authority_Dir & "/CURRENT.loam-writer-lock";
      Lock      : Lock_Handle;

      Manifest_Path : constant String := Authority_Dir & "/CURRENT";
      Man_Res       : Read_Manifest_Result;
      Failed_Fam    : Manifest_Family;

      Err_Buf : String (1 .. 128) := [others => ' '];
      Err_Len : Natural           := 0;
   begin
      --  1. Preflight sanity checks
      if Amount <= 0 then
         return Set_Error (Result, "Movement amount must be positive");
      end if;

      if From_Locus = To_Locus then
         return Set_Error (Result, "FROM and TO loci must be distinct");
      end if;

      if From_Locus'Length = 0 or else To_Locus'Length = 0 then
         return Set_Error (Result, "Locus tokens must not be empty");
      end if;

      --  2. Acquire exclusive writer ownership lock
      if not Acquire_Exclusive_Lock (Lock_Path, Lock) then
         return Set_Error (Result, "Failed to acquire writer ownership lock");
      end if;

      --  3. Re-read and verify selected manifest authority under lock
      Man_Res := Read_Manifest_File (Manifest_Path);
      if not Man_Res.Success then
         Release_Lock (Lock);
         return Set_Error
           (Result, "Failed to read CURRENT manifest: " &
            Man_Res.Error_Reason (1 .. Man_Res.Error_Len));
      end if;

      if not Verify_All_Objects (Authority_Dir, Man_Res.Manifest, Failed_Fam) then
         Release_Lock (Lock);
         return Set_Error
           (Result, "Pre-publication integrity check failed: " & Family_Name (Failed_Fam));
      end if;

      --  4. Verify Locus Admission
      declare
         Locus_Rel  : constant String :=
           Man_Res.Manifest (Family_Locus_Admission).Rel_Path
             (1 .. Man_Res.Manifest (Family_Locus_Admission).Path_Len);
         Locus_Full : constant String := Authority_Dir & "/" & Locus_Rel;
         Locus_Res  : constant Read_Locus_Result := Read_Locus_File (Locus_Full);
         From_Tok   : constant Locus_Id := (Token => Make_Token (From_Locus));
         To_Tok     : constant Locus_Id := (Token => Make_Token (To_Locus));
      begin
         if not Locus_Res.Success then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to read LocusAdmission vocabulary");
         end if;

         if not Admits_Locus (Locus_Res.Vocabulary, From_Tok) then
            Release_Lock (Lock);
            return Set_Error (Result, "Locus not approved for new publication: " & From_Locus);
         end if;

         if not Admits_Locus (Locus_Res.Vocabulary, To_Tok) then
            Release_Lock (Lock);
            return Set_Error (Result, "Locus not approved for new publication: " & To_Locus);
         end if;
      end;

      --  5. Read current contents of mutable authority families
      declare
         Event_Rel : constant String :=
           Man_Res.Manifest (Family_Event).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event).Path_Len);
         Val_Rel : constant String :=
           Man_Res.Manifest (Family_Actual_Validity).Rel_Path
             (1 .. Man_Res.Manifest (Family_Actual_Validity).Path_Len);
         Desc_Rel : constant String :=
           Man_Res.Manifest (Family_Event_Description).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event_Description).Path_Len);

         Event_Content : constant Unbounded_String :=
           Read_Entire_File (Authority_Dir & "/" & Event_Rel);
         Val_Content   : constant Unbounded_String :=
           Read_Entire_File (Authority_Dir & "/" & Val_Rel);
         Desc_Content  : constant Unbounded_String :=
           Read_Entire_File (Authority_Dir & "/" & Desc_Rel);
         Curr_Content  : constant Unbounded_String :=
           Read_Entire_File (Manifest_Path);
      begin
         if Length (Event_Content) = 0 or else Length (Val_Content) = 0
           or else Length (Desc_Content) = 0 or else Length (Curr_Content) = 0
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to read one or more authority object contents");
         end if;

         --  6. Determine next fresh EventId (Explicit_Id or record-N)
         declare
            Max_Record : constant Natural :=
              Extract_Max_Record_Number (To_String (Event_Content));
            Next_Num   : constant Natural := Max_Record + 1;
            Next_Id    : constant String  :=
              (if Explicit_Id'Length > 0 then Explicit_Id
               else "record-" & Natural_Image (Next_Num));

            --  New Event content
            New_Event_Append : constant String :=
              "EVENT" & ASCII.HT & Next_Id & ASCII.LF &
              "EFFECT" & ASCII.HT & "effect-1" & ASCII.HT & From_Locus &
              ASCII.HT & "jpy" & ASCII.HT & "-" & Quanta_Image (Amount) & ASCII.LF &
              "EFFECT" & ASCII.HT & "effect-2" & ASCII.HT & To_Locus &
              ASCII.HT & "jpy" & ASCII.HT & Quanta_Image (Amount) & ASCII.LF;

            New_Event_Text : constant String :=
              To_String (Event_Content) & New_Event_Append;

            --  New Validity content
            New_Val_Append : constant String :=
              "BASE" & ASCII.HT & Next_Id & ASCII.HT & Format_Iso_Date (Valid_On) & ASCII.LF;

            New_Val_Text : constant String :=
              To_String (Val_Content) & New_Val_Append;

            --  New Description content (if provided)
            New_Desc_Append : constant String :=
              (if Description'Length > 0 then
                 "DESC" & ASCII.HT & Next_Id & ASCII.HT & Escape_Text (Description) & ASCII.LF
               else "");

            New_Desc_Text : constant String :=
              To_String (Desc_Content) & New_Desc_Append;
         begin
            if not Commit_Authority_Update
              (Authority_Dir  => Authority_Dir,
               Manifest_Path  => Manifest_Path,
               Man_Res        => Man_Res,
               Curr_Content   => Curr_Content,
               New_Event_Text => New_Event_Text,
               New_Val_Text   => New_Val_Text,
               New_Desc_Text  => New_Desc_Text,
               Err_Buf        => Err_Buf,
               Err_Len        => Err_Len)
            then
               Release_Lock (Lock);
               return Set_Error (Result, Err_Buf (1 .. Err_Len));
            end if;

            Release_Lock (Lock);

            Result.Success := True;
            Result.Event_Id_Len := Next_Id'Length;
            Result.Event_Id_Str (1 .. Next_Id'Length) := Next_Id;
            return Result;
         end;
      end;

   exception
      when others =>
         Release_Lock (Lock);
         return Set_Error (Result, "Unexpected exception during publish");
   end Publish_Movement;

   function Publish_Reversal
     (Authority_Dir   : String;
      Target_Event_Id : String;
      Valid_On        : Date_Type;
      Description     : String := "") return Publish_Result
   is
      Result        : Publish_Result;
      Reversal_Id   : constant String := "reversal-of:" & Target_Event_Id;
      Lock_Path     : constant String := Authority_Dir & "/CURRENT.loam-writer-lock";
      Lock          : Lock_Handle;
      Manifest_Path : constant String := Authority_Dir & "/CURRENT";
      Man_Res       : Read_Manifest_Result;
      Failed_Fam    : Manifest_Family;
      Err_Buf       : String (1 .. 128) := [others => ' '];
      Err_Len       : Natural := 0;
   begin
      --  1. Preflight sanity checks
      if Target_Event_Id'Length = 0 then
         return Set_Error (Result, "Target event ID must not be empty");
      end if;

      if Target_Event_Id'Length > Max_Token_Length - 12 then
         return Set_Error (Result, "Target event ID too long for reversal");
      end if;

      if Target_Event_Id'Length >= 12
        and then Target_Event_Id (Target_Event_Id'First .. Target_Event_Id'First + 11) = "reversal-of:"
      then
         return Set_Error (Result, "Cannot revert an existing reversal event");
      end if;

      --  2. Acquire exclusive writer ownership lock
      if not Acquire_Exclusive_Lock (Lock_Path, Lock) then
         return Set_Error (Result, "Failed to acquire writer ownership lock");
      end if;

      --  3. Re-read and verify selected manifest authority under lock
      Man_Res := Read_Manifest_File (Manifest_Path);
      if not Man_Res.Success then
         Release_Lock (Lock);
         return Set_Error
           (Result, "Failed to read CURRENT manifest: " &
            Man_Res.Error_Reason (1 .. Man_Res.Error_Len));
      end if;

      if not Verify_All_Objects (Authority_Dir, Man_Res.Manifest, Failed_Fam) then
         Release_Lock (Lock);
         return Set_Error
           (Result, "Pre-reversal integrity check failed: " & Family_Name (Failed_Fam));
      end if;

      --  4. Read current Event memory and locate target event
      declare
         Event_Rel : constant String :=
           Man_Res.Manifest (Family_Event).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event).Path_Len);
         Val_Rel : constant String :=
           Man_Res.Manifest (Family_Actual_Validity).Rel_Path
             (1 .. Man_Res.Manifest (Family_Actual_Validity).Path_Len);
         Desc_Rel : constant String :=
           Man_Res.Manifest (Family_Event_Description).Rel_Path
             (1 .. Man_Res.Manifest (Family_Event_Description).Path_Len);

         Event_Full_Path : constant String := Authority_Dir & "/" & Event_Rel;
         Ev_Res          : constant Read_Result :=
           Read_Event_Memory_File (Event_Full_Path);

         Event_Content : constant Unbounded_String :=
           Read_Entire_File (Event_Full_Path);
         Val_Content   : constant Unbounded_String :=
           Read_Entire_File (Authority_Dir & "/" & Val_Rel);
         Desc_Content  : constant Unbounded_String :=
           Read_Entire_File (Authority_Dir & "/" & Desc_Rel);
         Curr_Content  : constant Unbounded_String :=
           Read_Entire_File (Manifest_Path);

         Target_Index : Natural := 0;
      begin
         if not Ev_Res.Success then
            Release_Lock (Lock);
            return Set_Error
              (Result, "Failed to parse Event memory: " &
               Ev_Res.Error_Reason (1 .. Ev_Res.Error_Len));
         end if;

         if Length (Event_Content) = 0 or else Length (Val_Content) = 0
           or else Length (Desc_Content) = 0 or else Length (Curr_Content) = 0
         then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to read one or more authority object contents");
         end if;

         --  Scan events: locate target and verify not already reversed
         for I in 1 .. Natural (Ev_Res.Events.Length) loop
            declare
               Ev     : constant Event := Ev_Res.Events.Element (I);
               Tok    : constant Token_Text := Id (Ev).Token;
               Id_Str : constant String := Tok.Value (1 .. Tok.Length);
            begin
               if Id_Str = Reversal_Id then
                  Release_Lock (Lock);
                  return Set_Error (Result, "Event is already reversed: " & Target_Event_Id);
               end if;

               if Id_Str = Target_Event_Id then
                  Target_Index := I;
               end if;
            end;
         end loop;

         if Target_Index = 0 then
            Release_Lock (Lock);
            return Set_Error (Result, "Target event not found: " & Target_Event_Id);
         end if;

         --  Build reverse event
         declare
            Target_Ev : constant Event := Ev_Res.Events.Element (Target_Index);
            Count     : constant Natural := Effect_Count (Target_Ev);
            New_Event_Append : Unbounded_String := Null_Unbounded_String;
         begin
            if Count = 0 then
               Release_Lock (Lock);
               return Set_Error (Result, "Target event has no effects to revert");
            end if;

            Append (New_Event_Append, "EVENT" & ASCII.HT & Reversal_Id & ASCII.LF);
            for I in 1 .. Count loop
               declare
                  Eff         : constant Effect := Effect_At (Target_Ev, I);
                  Eff_Key     : constant String := Eff.Key.Token.Value (1 .. Eff.Key.Token.Length);
                  Eff_Locus   : constant String := Eff.Locus.Token.Value (1 .. Eff.Locus.Token.Length);
                  Eff_Measure : constant String :=
                    Eff.Measure.Token.Value (1 .. Eff.Measure.Token.Length);
                  Inv_Quanta  : constant Quanta_Type := -Eff.Amount.Quanta;
               begin
                  Append
                    (New_Event_Append,
                     "EFFECT" & ASCII.HT & Eff_Key & ASCII.HT & Eff_Locus & ASCII.HT &
                     Eff_Measure & ASCII.HT & Quanta_Image (Inv_Quanta) & ASCII.LF);
               end;
            end loop;

            declare
               New_Event_Text : constant String :=
                 To_String (Event_Content) & To_String (New_Event_Append);

               New_Val_Append : constant String :=
                 "BASE" & ASCII.HT & Reversal_Id & ASCII.HT &
                 Format_Iso_Date (Valid_On) & ASCII.LF;
               New_Val_Text   : constant String :=
                 To_String (Val_Content) & New_Val_Append;

               Desc_Text : constant String :=
                 (if Description'Length > 0 then Description
                  else "Reversal of " & Target_Event_Id);
               New_Desc_Append : constant String :=
                 "DESC" & ASCII.HT & Reversal_Id & ASCII.HT &
                 Escape_Text (Desc_Text) & ASCII.LF;
               New_Desc_Text   : constant String :=
                 To_String (Desc_Content) & New_Desc_Append;
            begin
               if not Commit_Authority_Update
                 (Authority_Dir  => Authority_Dir,
                  Manifest_Path  => Manifest_Path,
                  Man_Res        => Man_Res,
                  Curr_Content   => Curr_Content,
                  New_Event_Text => New_Event_Text,
                  New_Val_Text   => New_Val_Text,
                  New_Desc_Text  => New_Desc_Text,
                  Err_Buf        => Err_Buf,
                  Err_Len        => Err_Len)
               then
                  Release_Lock (Lock);
                  return Set_Error (Result, Err_Buf (1 .. Err_Len));
               end if;

               Release_Lock (Lock);

               Result.Success := True;
               Result.Event_Id_Len := Reversal_Id'Length;
               Result.Event_Id_Str (1 .. Reversal_Id'Length) := Reversal_Id;
               return Result;
            end;
         end;
      end;

   exception
      when others =>
         Release_Lock (Lock);
         return Set_Error (Result, "Unexpected exception during reversal");
   end Publish_Reversal;

end HRA_N.Application.Publisher;
