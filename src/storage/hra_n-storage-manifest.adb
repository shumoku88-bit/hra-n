-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Manifest
-------------------------------------------------------------------------------

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO;
with GNAT.SHA256;

package body HRA_N.Storage.Manifest is

   function Family_Name (Family : Manifest_Family) return String is
   begin
      case Family is
         when Family_Event              => return "Event";
         when Family_Actual_Validity    => return "ActualValidity";
         when Family_Event_Description  => return "EventDescription";
         when Family_Relation_Unit      => return "RelationUnit";
         when Family_Relation_Discharge => return "RelationDischarge";
         when Family_Locus_Admission    => return "LocusAdmission";
      end case;
   end Family_Name;

   function Parse_Family
     (Name   : String;
      Family : out Manifest_Family) return Boolean
   is
   begin
      Family := Family_Event;
      if Name = "Event" then
         Family := Family_Event;
         return True;
      elsif Name = "ActualValidity" then
         Family := Family_Actual_Validity;
         return True;
      elsif Name = "EventDescription" then
         Family := Family_Event_Description;
         return True;
      elsif Name = "RelationUnit" then
         Family := Family_Relation_Unit;
         return True;
      elsif Name = "RelationDischarge" then
         Family := Family_Relation_Discharge;
         return True;
      elsif Name = "LocusAdmission" then
         Family := Family_Locus_Admission;
         return True;
      else
         return False;
      end if;
   end Parse_Family;

   type Field_Slice is record
      First : Positive;
      Last  : Natural;
   end record;

   type Field_Array is array (1 .. 8) of Field_Slice;

   procedure Split_Tabs
     (Line   : String;
      Fields : out Field_Array;
      Count  : out Natural)
   is
      Pos   : Positive := Line'First;
      Idx   : Natural  := 0;
      Start : Positive;
   begin
      Count := 0;
      if Line'Length = 0 then
         return;
      end if;

      while Pos <= Line'Last and then Idx < Fields'Last loop
         Start := Pos;
         while Pos <= Line'Last and then Line (Pos) /= ASCII.HT loop
            Pos := Pos + 1;
         end loop;

         Idx := Idx + 1;
         Fields (Idx) := (First => Start, Last => Pos - 1);

         if Pos <= Line'Last and then Line (Pos) = ASCII.HT then
            Pos := Pos + 1;
         end if;
      end loop;

      Count := Idx;
   end Split_Tabs;

   function Set_Error
     (Result   : in out Read_Manifest_Result;
      Line_Num : Natural;
      Msg      : String) return Read_Manifest_Result
   is
   begin
      Result.Success      := False;
      Result.Error_Line   := Line_Num;
      Result.Error_Len    := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Error;

   function Read_Manifest_File (Path : String) return Read_Manifest_Result is
      File        : File_Type;
      Result      : Read_Manifest_Result;
      Line_Num    : Natural := 0;
      Fields      : Field_Array;
      Field_Count : Natural;
   begin
      begin
         Open (File, In_File, Path);
      exception
         when others =>
            return Set_Error (Result, 0, "Cannot open manifest file: " & Path);
      end;

      while not End_Of_File (File) loop
         declare
            Line : constant String := Get_Line (File);
         begin
            Line_Num := Line_Num + 1;

            if Line'Length > 0 then
               Split_Tabs (Line, Fields, Field_Count);

               if Line_Num = 1 then
                  if Field_Count /= 2
                    or else Line (Fields (1).First .. Fields (1).Last) /= "LOAM-MOVEMENT-MANIFEST"
                    or else Line (Fields (2).First .. Fields (2).Last) /= "2"
                  then
                     Close (File);
                     return Set_Error (Result, 1, "Invalid header, expected LOAM-MOVEMENT-MANIFEST 2");
                  end if;
               else
                  if Field_Count /= 3 then
                     Close (File);
                     return Set_Error (Result, Line_Num, "Malformed manifest row (expected 3 fields)");
                  end if;

                  declare
                     Fam_Str  : constant String := Line (Fields (1).First .. Fields (1).Last);
                     Path_Str : constant String := Line (Fields (2).First .. Fields (2).Last);
                     Hash_Str : constant String := Line (Fields (3).First .. Fields (3).Last);
                     Fam      : Manifest_Family;
                  begin
                     if not Parse_Family (Fam_Str, Fam) then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Unrecognized manifest family: " & Fam_Str);
                     end if;

                     if Result.Manifest (Fam).Present then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Duplicate family in manifest: " & Fam_Str);
                     end if;

                     if Hash_Str'Length /= 64 then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Invalid SHA-256 digest length");
                     end if;

                     if Path_Str'Length > Max_Path_Length then
                        Close (File);
                        return Set_Error (Result, Line_Num, "Path exceeds maximum length");
                     end if;

                     Result.Manifest (Fam).Present  := True;
                     Result.Manifest (Fam).Path_Len := Path_Str'Length;
                     Result.Manifest (Fam).Rel_Path (1 .. Path_Str'Length) := Path_Str;
                     Result.Manifest (Fam).Digest   := Hash_Str;
                  end;
               end if;
            end if;
         end;
      end loop;

      Close (File);
      Result.Success := True;
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Set_Error (Result, Line_Num, "Unexpected error reading manifest");
   end Read_Manifest_File;

   function Compute_File_Hash
     (File_Path : String;
      Digest    : out Sha256_Digest) return Boolean
   is
      use Ada.Streams.Stream_IO;
      File   : Ada.Streams.Stream_IO.File_Type;
      Buffer : Stream_Element_Array (1 .. 4096);
      Last   : Stream_Element_Offset;
      Ctx    : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
   begin
      begin
         Open (File, In_File, File_Path);
      exception
         when others =>
            return False;
      end;

      while not End_Of_File (File) loop
         Read (File, Buffer, Last);
         declare
            Str : String (1 .. Natural (Last));
         begin
            for I in 1 .. Last loop
               Str (Natural (I)) := Character'Val (Buffer (I));
            end loop;
            GNAT.SHA256.Update (Ctx, Str);
         end;
      end loop;

      Close (File);
      Digest := GNAT.SHA256.Digest (Ctx);
      return True;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return False;
   end Compute_File_Hash;

   function Verify_Object_Integrity
     (Base_Dir : String;
      Item     : Manifest_Item) return Boolean
   is
      Actual_Digest : Sha256_Digest;
      Full_Path     : constant String :=
        Base_Dir & "/" & Item.Rel_Path (1 .. Item.Path_Len);
   begin
      if not Item.Present then
         return False;
      end if;

      if not Compute_File_Hash (Full_Path, Actual_Digest) then
         return False;
      end if;

      return Actual_Digest = Item.Digest;
   end Verify_Object_Integrity;

   function Verify_All_Objects
     (Base_Dir      : String;
      Manifest      : Manifest_Record;
      Failed_Family : out Manifest_Family) return Boolean
   is
   begin
      for Fam in Manifest_Family loop
         if Manifest (Fam).Present then
            if not Verify_Object_Integrity (Base_Dir, Manifest (Fam)) then
               Failed_Family := Fam;
               return False;
            end if;
         end if;
      end loop;
      return True;
   end Verify_All_Objects;

end HRA_N.Storage.Manifest;
