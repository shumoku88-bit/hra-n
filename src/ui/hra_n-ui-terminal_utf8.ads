-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Terminal_UTF8
--
--  Terminal UTF-8 locale activation, wcwidth display measurement, and safe
--  clipping without mid-glyph or mid-byte fragmentation.
-------------------------------------------------------------------------------

package HRA_N.UI.Terminal_UTF8 is

   --  Activate the process locale for terminal UTF-8 operations. Call once
   --  at application startup before terminal cell layout or Init_Screen.
   procedure Initialize;

   --  Draw one UTF-8 line on the standard curses window without splitting a
   --  multi-byte code point or a multi-column terminal glyph.
   procedure Add_Line
     (Line        : Natural;
      Column      : Natural;
      Max_Columns : Natural;
      Text        : String);

   --  Compute terminal cell display width of a UTF-8 string according to
   --  the active system locale / wcwidth. Returns 0 if text is empty or invalid.
   function Display_Width (Text : String) return Natural;

   --  Slice a UTF-8 string by display column offset and width without breaking
   --  multi-byte code points or multi-column glyphs.
   function Slice
     (Text         : String;
      Start_Column : Natural;
      Max_Columns  : Natural) return String;

   subtype Unicode_Code_Point is Natural range 0 .. 16#10FFFF#;

   function Is_Unicode_Scalar (Code_Point : Natural) return Boolean;

   function Append_Code_Point
     (Text       : String;
      Code_Point : Unicode_Code_Point) return String
     with Pre => Is_Unicode_Scalar (Code_Point);

   function Drop_Last_Code_Point (Text : String) return String;

end HRA_N.UI.Terminal_UTF8;
