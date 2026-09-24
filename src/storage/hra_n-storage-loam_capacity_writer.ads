-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Capacity_Writer
--
--  Direct publisher for LOAM-NORMALIZED-CAPACITY v1 authority.
--  Publishes balanced Capacity movements (transfers and rebalances)
--  under exclusive file locking and snapshot-bound verification.
--  Strictly enforces universal conservation (sum = 0) and non-negative
--  Purpose entitlements.
-------------------------------------------------------------------------------

with HRA_N.Core.Capacity; use HRA_N.Core.Capacity;
with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Capacity_Writer is

   Max_Draft_Changes : constant := 16;

   subtype Draft_Count_Type is Natural range 0 .. Max_Draft_Changes;
   subtype Draft_Index_Type is Positive range 1 .. Max_Draft_Changes;
   type Draft_Change_Array is array (Draft_Index_Type) of Capacity_Change;

   type Capacity_Draft is record
      Effective_On : Date_Type;
      Currency     : Token_Text;
      Change_Count : Draft_Count_Type := 0;
      Changes      : Draft_Change_Array := [others => Empty_Change];
   end record;

   type Publish_Result is record
      Success      : Boolean := False;
      Movement_Id  : String (1 .. 64) := [others => ' '];
      Movement_Len : Natural := 0;
      Error_Reason : String (1 .. 192) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   --  Create a transfer draft from Source to Destination.
   function Make_Transfer_Draft
     (Source       : Capacity_Coordinate;
      Destination  : Capacity_Coordinate;
      Amount       : Quanta_Type;
      Effective_On : Date_Type;
      Currency     : Token_Text := Make_Token ("jpy")) return Capacity_Draft;

   --  Publish one balanced Capacity draft to Root_Path/capacity.loam.
   --  Atomically publishes under .loam-writer-lock with readback verification.
   function Publish_Capacity
     (Root_Path : String;
      Draft     : Capacity_Draft) return Publish_Result;

end HRA_N.Storage.Loam_Capacity_Writer;
