package HRA_N.UI.Terminal is

   procedure Put_Clipped
     (Row  : Natural;
      Text : String);

   function Rows return Natural;
   function Columns return Natural;

end HRA_N.UI.Terminal;
