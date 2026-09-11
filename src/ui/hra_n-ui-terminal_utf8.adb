-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Terminal_UTF8
-------------------------------------------------------------------------------

with Interfaces.C;
with Interfaces.C.Strings;

package body HRA_N.UI.Terminal_UTF8 is

   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;
   use type C.int;
   use type C_Strings.chars_ptr;

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

      if Result /= 0 then
         raise Program_Error with "unable to render UTF-8 terminal line";
      end if;
   exception
      when others =>
         if Ptr /= C_Strings.Null_Ptr then
            C_Strings.Free (Ptr);
         end if;
         raise;
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
