with HRA_N.UI.Terminal_UTF8;
with Test_Support; use Test_Support;

package body Test_Terminal_UTF8 is

   package UTF8 renames HRA_N.UI.Terminal_UTF8;
   use type UTF8.Decode_Status;

   procedure Run is
      State  : UTF8.Decoder_State := UTF8.Initial_Decoder_State;
      Result : UTF8.Decode_Result;
   begin
      Result := UTF8.Feed_Keystroke (State, Character'Pos ('Z'));
      Assert
        (Result.Status = UTF8.Decoded_Character
         and then Result.Code_Point = Character'Pos ('Z'),
         "ASCII keystroke decodes directly");

      Result := UTF8.Feed_Keystroke (State, 263);
      Assert
        (Result.Status = UTF8.Decoded_Special_Key
         and then Result.Key_Code = 263,
         "curses special key remains outside Unicode input");

      Result := UTF8.Feed_Keystroke (State, 16#E6#);
      Assert (Result.Status = UTF8.Incomplete, "Japanese byte 1 is incomplete");
      Result := UTF8.Feed_Keystroke (State, 16#98#);
      Assert (Result.Status = UTF8.Incomplete, "Japanese byte 2 is incomplete");
      Result := UTF8.Feed_Keystroke (State, 16#BC#);
      Assert
        (Result.Status = UTF8.Decoded_Character
         and then Result.Code_Point = 16#663C#,
         "Japanese UTF-8 sequence decodes to one code point");

      Assert
        (UTF8.Append_Code_Point ("", 16#663C#) =
           Character'Val (16#E6#) & Character'Val (16#98#) &
           Character'Val (16#BC#),
         "decoded Japanese code point re-encodes to exact UTF-8 bytes");

      Result := UTF8.Feed_Keystroke (State, 16#F0#);
      Assert (Result.Status = UTF8.Incomplete, "four-byte sequence begins");
      Result := UTF8.Feed_Keystroke (State, 16#9F#);
      Assert (Result.Status = UTF8.Incomplete, "four-byte sequence continues");
      Result := UTF8.Feed_Keystroke (State, 16#90#);
      Assert (Result.Status = UTF8.Incomplete, "four-byte sequence remains incomplete");
      Result := UTF8.Feed_Keystroke (State, 16#B8#);
      Assert
        (Result.Status = UTF8.Decoded_Character
         and then Result.Code_Point = 16#1F438#,
         "four-byte UTF-8 sequence decodes exactly");

      Result := UTF8.Feed_Keystroke (State, 16#80#);
      Assert
        (Result.Status = UTF8.Invalid_Sequence,
         "orphan continuation byte is rejected");

      Result := UTF8.Feed_Keystroke (State, 16#C0#);
      Assert
        (Result.Status = UTF8.Invalid_Sequence,
         "overlong UTF-8 lead byte is rejected");

      Result := UTF8.Feed_Keystroke (State, 16#E5#);
      Assert (Result.Status = UTF8.Incomplete, "partial sequence starts");
      Result := UTF8.Feed_Keystroke (State, 259);
      Assert
        (Result.Status = UTF8.Decoded_Special_Key
         and then Result.Key_Code = 259,
         "special key cancels a partial UTF-8 sequence");
      Result := UTF8.Feed_Keystroke (State, 16#AE#);
      Assert
        (Result.Status = UTF8.Invalid_Sequence,
         "decoder state resets after a special key");

      Report_Summary ("Terminal UTF-8");
   end Run;

end Test_Terminal_UTF8;
