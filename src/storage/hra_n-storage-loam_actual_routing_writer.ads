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

   type Publish_Result is record
      Success      : Boolean := False;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Publish a new routing assertion in Root_Path/actual-routing.loam.
   --  Verifies that Locus is admitted in locus-admission.loam.
   --  Verifies that (Locus, Effective) coordinate is not duplicate.
   --  Atomically publishes under .loam-writer-lock with readback verification.
   function Publish_Route
     (Root_Path : String;
      Draft     : Routing_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Actual_Routing_Writer;
