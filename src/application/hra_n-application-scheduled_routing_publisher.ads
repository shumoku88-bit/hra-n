-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Scheduled_Routing_Publisher
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Scheduled; use HRA_N.Core.Scheduled;

package HRA_N.Application.Scheduled_Routing_Publisher is

   type Route_Target is (Target_Managed, Target_Unmanaged);
   type Publish_Result is record
      Success      : Boolean           := False;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural           := 0;
   end record;

   function Publish
     (Routing_Path   : String;
      Scheduled_Path : String;
      Scheduled      : Scheduled_Id;
      Locus          : Locus_Id;
      Effective_On   : Date_Type;
      Target         : Route_Target;
      Purpose        : Token_Text := (Length => 0, Value => [others => ' ']))
      return Publish_Result;

end HRA_N.Application.Scheduled_Routing_Publisher;
