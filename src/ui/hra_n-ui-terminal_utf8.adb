-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Terminal_UTF8
-------------------------------------------------------------------------------

with Interfaces.C;
with Interfaces.C.Strings;
with Terminal_Interface.Curses;

package body HRA_N.UI.Terminal_UTF8 is

   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;
   package Curses renames Terminal_Interface.Curses;
   use type C.int;
   use type C_Strings.chars_ptr;
   use type Curses.Real_Key_Code;

   function C_Initialize return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_n_terminal_utf8_initialize";

   function C_Display_Width
     (Text : C_Strings.chars_ptr) return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_n_terminal_utf8_display_width";

   function C_Add_Line
     (Line        : C.int;
      Column      : C.int;
      Text        : C_Strings.chars_ptr;
      Max_Columns : C.int) return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_n_terminal_utf8_add_line";

   function C_Slice
     (Text         : C_Strings.chars_ptr;
      Start_Column : C.int;
      Max_Columns  : C.int;
      Out_Buf      : C_Strings.chars_ptr;
      Out_Buf_Size : C.int) return C.int
     with Import,
          Convention    => C,
          External_Name => "hra_n_terminal_utf8_slice";

   procedure Initialize is
   begin
      if C_Initialize /= 0 then
         raise Program_Error with "unable to activate terminal UTF-8 locale";
      end if;
   end Initialize;

   procedure Add_Line
     (Line        : Natural;
      Column      : Natural;
      Max_Columns : Natural;
      Text        : String)
   is
      Ptr    : C_Strings.chars_ptr := C_Strings.New_String (Text);
      Result : C.int;
   begin
      Result :=
        C_Add_Line
          (C.int (Line),
           C.int (Column),
           Ptr,
           C.int (Max_Columns));
      C_Strings.Free (Ptr);

      declare
         Ignored : C.int renames Result;
      begin
         null;
      end;
   exception
      when others =>
         if Ptr /= C_Strings.Null_Ptr then
            C_Strings.Free (Ptr);
         end if;
   end Add_Line;

   function Display_Width (Text : String) return Natural is
      Ptr    : C_Strings.chars_ptr := C_Strings.New_String (Text);
      Result : C.int;
   begin
      Result := C_Display_Width (Ptr);
      C_Strings.Free (Ptr);

      if Result < 0 then
         return 0;
      else
         return Natural (Result);
      end if;
   exception
      when others =>
         if Ptr /= C_Strings.Null_Ptr then
            C_Strings.Free (Ptr);
         end if;
         return 0;
   end Display_Width;

   function Slice
     (Text         : String;
      Start_Column : Natural;
      Max_Columns  : Natural) return String
   is
      Ptr        : C_Strings.chars_ptr := C_Strings.New_String (Text);
      Buf_Len    : constant Natural := Text'Length * 4 + 16;
      Out_Ptr    : C_Strings.chars_ptr :=
        C_Strings.New_String (String'(1 .. Buf_Len => ' '));
      Result     : C.int;
   begin
      Result :=
        C_Slice
          (Ptr,
           C.int (Start_Column),
           C.int (Max_Columns),
           Out_Ptr,
           C.int (Buf_Len));
      C_Strings.Free (Ptr);

      if Result /= 0 then
         C_Strings.Free (Out_Ptr);
         return "";
      else
         declare
            Ret : constant String := C_Strings.Value (Out_Ptr);
         begin
            C_Strings.Free (Out_Ptr);
            return Ret;
         end;
      end if;
   exception
      when others =>
         if Ptr /= C_Strings.Null_Ptr then
            C_Strings.Free (Ptr);
         end if;
         if Out_Ptr /= C_Strings.Null_Ptr then
            C_Strings.Free (Out_Ptr);
         end if;
         return "";
   end Slice;

   function Is_Unicode_Scalar (Code_Point : Natural) return Boolean is
     (Code_Point in 0 .. 16#D7FF#
      or Code_Point in 16#E000# .. 16#10FFFF#);

   function Initial_Decoder_State return Decoder_State is
     ((Remaining_Bytes => 0,
       Accumulator     => 0,
       Min_Code_Point  => 0,
       Max_Code_Point  => 0));

   function Feed_Keystroke
     (State : in out Decoder_State;
      Key   : Integer) return Decode_Result
   is
   begin
      if Key >= 256 then
         State := Initial_Decoder_State;
         return (Status => Decoded_Special_Key, Key_Code => Key);
      elsif Key < 0 then
         State := Initial_Decoder_State;
         return (Status => Invalid_Sequence);
      end if;

      if State.Remaining_Bytes = 0 then
         if Key in 0 .. 127 then
            return
              (Status => Decoded_Character,
               Code_Point => Unicode_Code_Point (Key));
         elsif Key in 16#C2# .. 16#DF# then
            State :=
              (Remaining_Bytes => 1,
               Accumulator     => Key - 16#C0#,
               Min_Code_Point  => 16#80#,
               Max_Code_Point  => 16#7FF#);
            return (Status => Incomplete);
         elsif Key in 16#E0# .. 16#EF# then
            State :=
              (Remaining_Bytes => 2,
               Accumulator     => Key - 16#E0#,
               Min_Code_Point  => 16#800#,
               Max_Code_Point  => 16#FFFF#);
            return (Status => Incomplete);
         elsif Key in 16#F0# .. 16#F4# then
            State :=
              (Remaining_Bytes => 3,
               Accumulator     => Key - 16#F0#,
               Min_Code_Point  => 16#10000#,
               Max_Code_Point  => 16#10FFFF#);
            return (Status => Incomplete);
         else
            return (Status => Invalid_Sequence);
         end if;
      elsif Key in 16#80# .. 16#BF# then
         State.Accumulator := State.Accumulator * 64 + (Key - 16#80#);
         State.Remaining_Bytes := State.Remaining_Bytes - 1;
         if State.Remaining_Bytes = 0 then
            declare
               Code   : constant Natural := State.Accumulator;
               Min_CP : constant Natural := State.Min_Code_Point;
               Max_CP : constant Natural := State.Max_Code_Point;
            begin
               State := Initial_Decoder_State;
               if Code >= Min_CP
                 and then Code <= Max_CP
                 and then Is_Unicode_Scalar (Code)
               then
                  return
                    (Status => Decoded_Character,
                     Code_Point => Unicode_Code_Point (Code));
               else
                  return (Status => Invalid_Sequence);
               end if;
            end;
         else
            return (Status => Incomplete);
         end if;
      else
         State := Initial_Decoder_State;
         return (Status => Invalid_Sequence);
      end if;
   end Feed_Keystroke;

   function Read_Input return Input_Event is
      State : Decoder_State := Initial_Decoder_State;
   begin
      loop
         declare
            Key : constant Curses.Real_Key_Code := Curses.Get_Keystroke;
         begin
            if Key = -1 then
               raise Program_Error with "error reading terminal keystroke";
            end if;

            declare
               Result : constant Decode_Result :=
                 Feed_Keystroke (State, Integer (Key));
            begin
               case Result.Status is
                  when Decoded_Character =>
                     return
                       (Kind => Character_Input,
                        Code_Point => Result.Code_Point);
                  when Decoded_Special_Key =>
                     return
                       (Kind => Special_Key_Input,
                        Key_Code => Result.Key_Code);
                  when Incomplete | Invalid_Sequence =>
                     null;
               end case;
            end;
         end;
      end loop;
   end Read_Input;

   function Append_Code_Point
     (Text       : String;
      Code_Point : Unicode_Code_Point) return String
   is
      function Byte (Value : Natural) return Character is
        (Character'Val (Value));
   begin
      if Code_Point <= 16#7F# then
         return Text & Byte (Code_Point);
      elsif Code_Point <= 16#7FF# then
         return
           Text &
           Byte (16#C0# + Code_Point / 64) &
           Byte (16#80# + Code_Point mod 64);
      elsif Code_Point <= 16#FFFF# then
         return
           Text &
           Byte (16#E0# + Code_Point / 4096) &
           Byte (16#80# + (Code_Point / 64) mod 64) &
           Byte (16#80# + Code_Point mod 64);
      else
         return
           Text &
           Byte (16#F0# + Code_Point / 262144) &
           Byte (16#80# + (Code_Point / 4096) mod 64) &
           Byte (16#80# + (Code_Point / 64) mod 64) &
           Byte (16#80# + Code_Point mod 64);
      end if;
   end Append_Code_Point;

   function Drop_Last_Code_Point (Text : String) return String is
      Start : Integer;
   begin
      if Text'Length = 0 then
         return "";
      end if;

      Start := Text'Last;
      while Start > Text'First
        and then Character'Pos (Text (Start)) in 16#80# .. 16#BF#
      loop
         Start := Start - 1;
      end loop;

      if Start = Text'First then
         return "";
      else
         return Text (Text'First .. Start - 1);
      end if;
   end Drop_Last_Code_Point;

end HRA_N.UI.Terminal_UTF8;
