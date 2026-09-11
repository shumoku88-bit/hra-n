-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Terminal
-------------------------------------------------------------------------------

package HRA_N.UI.Terminal is

   procedure Initialize;

   procedure Put_Clipped
     (Row  : Natural;
      Text : String);

   procedure Put_Clipped
     (Row    : Natural;
      Column : Natural;
      Text   : String);

   function Display_Width (Text : String) return Natural;

   function Rows return Natural;
   function Columns return Natural;

end HRA_N.UI.Terminal;
