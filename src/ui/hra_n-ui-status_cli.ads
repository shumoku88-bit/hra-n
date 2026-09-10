with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;

package HRA_N.UI.Status_CLI is
   procedure Display_Status
     (Paths : Path_Config; Events : Event_Vectors.Vector; Success : out Boolean);
end HRA_N.UI.Status_CLI;
