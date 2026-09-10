-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Relation_CLI
-------------------------------------------------------------------------------

with HRA_N.Storage.Manifest; use HRA_N.Storage.Manifest;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;

package HRA_N.UI.Relation_CLI is

   procedure Display_Relations
     (Authority_Dir : String;
      Manifest      : Manifest_Record;
      Events        : Event_Vectors.Vector;
      Success       : out Boolean);

end HRA_N.UI.Relation_CLI;
