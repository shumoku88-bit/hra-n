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

   type Input_Kind is (Character_Input, Special_Key_Input);

   type Input_Event (Kind : Input_Kind := Character_Input) is record
      case Kind is
         when Character_Input =>
            Code_Point : Unicode_Code_Point;
         when Special_Key_Input =>
            Key_Code : Integer;
      end case;
   end record;

   type Decode_Status is
     (Incomplete,
      Decoded_Character,
      Decoded_Special_Key,
      Invalid_Sequence);

   type Decode_Result (Status : Decode_Status := Incomplete) is record
      case Status is
         when Decoded_Character =>
            Code_Point : Unicode_Code_Point;
         when Decoded_Special_Key =>
            Key_Code : Integer;
         when Incomplete | Invalid_Sequence =>
            null;
      end case;
   end record;

   type Decoder_State is private;

   function Initial_Decoder_State return Decoder_State;

   --  Decode one raw curses keystroke. Octets form UTF-8 characters while
   --  KEY_* values remain a separate namespace.
   function Feed_Keystroke
     (State : in out Decoder_State;
      Key   : Integer) return Decode_Result;

   --  Blocking read which never exposes an incomplete UTF-8 sequence.
   function Read_Input return Input_Event;

   function Append_Code_Point
     (Text       : String;
      Code_Point : Unicode_Code_Point) return String
     with Pre => Is_Unicode_Scalar (Code_Point);

   function Drop_Last_Code_Point (Text : String) return String;

private

   type Decoder_State is record
      Remaining_Bytes : Natural range 0 .. 3 := 0;
      Accumulator     : Natural := 0;
      Min_Code_Point  : Natural := 0;
      Max_Code_Point  : Natural := 0;
   end record;

end HRA_N.UI.Terminal_UTF8;
