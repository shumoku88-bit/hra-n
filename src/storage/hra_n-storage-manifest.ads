-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Manifest
--
--  Parses LOAM-MOVEMENT-MANIFEST v2 and verifies content-addressable SHA-256
--  integrity of referenced authority objects.
--
--  Design Rationale:
--  In Loam, CURRENT represents the sole operational manifest authority.
--  Each admitted object is content-addressed by its exact SHA-256 digest.
--  Any hash mismatch or missing object causes immediate fail-closed rejection.
-------------------------------------------------------------------------------

package HRA_N.Storage.Manifest is

   --  Exact 64-character lowercase hexadecimal SHA-256 digest.
   subtype Sha256_Digest is String (1 .. 64);

   --  Maximum length of object relative paths (e.g. objects/Event/<hash>.loam).
   Max_Path_Length : constant := 256;

   --  Enumeration of recognized Loam movement manifest families.
   type Manifest_Family is
     (Family_Event,
      Family_Actual_Validity,
      Family_Event_Description,
      Family_Relation_Unit,
      Family_Relation_Discharge,
      Family_Locus_Admission);

   function Family_Name (Family : Manifest_Family) return String;

   function Parse_Family
     (Name   : String;
      Family : out Manifest_Family) return Boolean;

   --  One recorded manifest item linking a family to its relative object path
   --  and expected SHA-256 digest.
   type Manifest_Item is record
      Present  : Boolean       := False;
      Rel_Path : String (1 .. Max_Path_Length) := [others => ' '];
      Path_Len : Natural       := 0;
      Digest   : Sha256_Digest := [others => ' '];
   end record;

   --  Collection of all families declared in one manifest file.
   type Manifest_Record is array (Manifest_Family) of Manifest_Item;

   type Read_Manifest_Result is record
      Success      : Boolean         := False;
      Manifest     : Manifest_Record;
      Error_Line   : Natural         := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural         := 0;
   end record;

   --  Parse a LOAM-MOVEMENT-MANIFEST v2 file.
   function Read_Manifest_File (Path : String) return Read_Manifest_Result;

   --  Compute raw stream SHA-256 digest of an on-disk file.
   function Compute_File_Hash
     (File_Path : String;
      Digest    : out Sha256_Digest) return Boolean;

   --  Verify that a referenced object file exists on disk and its raw
   --  SHA-256 digest exactly matches the manifest's declared digest.
   function Verify_Object_Integrity
     (Base_Dir : String;
      Item     : Manifest_Item) return Boolean;

   --  Verify all declared objects in a manifest record against disk.
   function Verify_All_Objects
     (Base_Dir      : String;
      Manifest      : Manifest_Record;
      Failed_Family : out Manifest_Family) return Boolean;

end HRA_N.Storage.Manifest;
