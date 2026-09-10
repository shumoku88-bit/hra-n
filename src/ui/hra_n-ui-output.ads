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

package HRA_N.UI.Output is

   procedure Put (Text : String);
   procedure Put_Line (Text : String);
   procedure New_Line;

   procedure Put_Error (Text : String);
   procedure Put_Error_Line (Text : String);

end HRA_N.UI.Output;
