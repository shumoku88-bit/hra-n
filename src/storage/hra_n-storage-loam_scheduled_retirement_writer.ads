-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Scheduled_Retirement_Writer
--
--  Canonical Scheduled retirement publisher.
--
--  Retirement modifies scheduled.loam only, but it holds the shared
--  Scheduled -> Actual ownership interval while classifying any retained
--  completion claim.  This prevents retirement from competing with either a
--  completed or interrupted Scheduled completion.
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Storage.Loam_Scheduled_Retirement_Writer is

   type Retirement_Publication_State is
     (Retirement_Not_Published,
      Retirement_Published_Fresh);

   type Publish_Result is record
      State        : Retirement_Publication_State := Retirement_Not_Published;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Publish_Retirement
     (Root_Path : String;
      Scheduled : Scheduled_Id) return Publish_Result;

end HRA_N.Storage.Loam_Scheduled_Retirement_Writer;
