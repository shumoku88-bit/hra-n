-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Output
--
--  Direct, exact UTF-8 byte stream output to standard terminal descriptors.
--
--  Design Rationale:
--  GNAT's Ada.Text_IO may transcode Character values (128..255) according
--  to Latin-1 wide-character encoding rules when UTF-8 locale is detected,
--  causing destructive double-encoding of pre-encoded UTF-8 strings.
--  Direct OS write guarantees zero transcoding and bit-exact UTF-8 fidelity.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.UI.Output is

   procedure Put (Text : String);
   procedure Put_Line (Text : String);
   procedure New_Line;

   procedure Put_Error (Text : String);
   procedure Put_Error_Line (Text : String);

   ----------------------------------------------------------------------------
   --  East Asian Wide-Character Aware Formatting
   ----------------------------------------------------------------------------
   --  UTF-8 sequences from the CJK ranges occupy two terminal columns per
   --  code point. Display_Width measures terminal columns rather than bytes
   --  so that mixed ASCII/Japanese rows align correctly.

   function Display_Width (S : String) return Natural;

   function Pad_Right (S : String; Width : Positive) return String;
   function Pad_Left (S : String; Width : Positive) return String;

   --  Format integer amount with comma thousands separators (e.g. 225,276)
   function Format_Amount (Val : Quanta_Type) return String;

end HRA_N.UI.Output;
