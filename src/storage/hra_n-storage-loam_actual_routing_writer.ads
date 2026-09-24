-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Routing_Writer
--
--  Direct publisher for LOAM-ACTUAL-ROUTING v1 authority.
--  Appends new routing assertions (managed purpose or unmanaged) over effective
--  coordinates under exclusive file locking and snapshot-bound verification.
--  Rejects duplicate (Locus, Effective_Kind, Effective_On) coordinates.
-------------------------------------------------------------------------------

with HRA_N.Core.Actual_Routing; use HRA_N.Core.Actual_Routing;
with HRA_N.Core.Types;          use HRA_N.Core.Types;
with HRA_N.Core.Validity;       use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Actual_Routing_Writer is

   type Routing_Draft is record
      Locus          : Locus_Id;
      Effective_Kind : Routing_Effective_Kind := Routing_Initial;
      Effective_On   : Date_Type             := (Year => 1900, Month => 1, Day => 1);
      Managed        : Boolean               := False;
      Purpose        : Token_Text;
   end record;

   type Routing_Publish_Status is
     (Invalid_Root_Directory,
      Invalid_Locus_Token,
      Invalid_Purpose_Token,
      Invalid_Effective_Date,
      Locus_Admission_Missing,
      Locus_Admission_Read_Error,
      Locus_Not_Admitted,
      Lock_Failure,
      Cannot_Read_File,
      Corrupt_Existing_File,
      Duplicate_Coordinate,
      Verification_Failure,
      Atomic_Write_Failure,
      Readback_Failure,
      Internal_Error);

   type Publish_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            null;
         when False =>
            Status       : Routing_Publish_Status := Internal_Error;
            Error_Reason : String (1 .. 192) := [others => ' '];
            Error_Len    : Natural := 0;
      end case;
   end record;

   function Format_Error (Result : Publish_Result) return String;

   --  Publish a new routing assertion in Root_Path/actual-routing.loam.
   --  Verifies that Locus is admitted in locus-admission.loam.
   --  Verifies that (Locus, Effective) coordinate is not duplicate.
   --  Atomically publishes under .loam-writer-lock with readback verification.
   function Publish_Route
     (Root_Path : String;
      Draft     : Routing_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Actual_Routing_Writer;
