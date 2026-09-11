-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package spec: HRA_N.UI.Terminal_Style
-------------------------------------------------------------------------------

package HRA_N.UI.Terminal_Style is

   type Semantic_Style is
     (Plain_Style,
      Header_Style,
      Muted_Style,
      Positive_Style,
      Negative_Style,
      Warning_Style,
      Error_Style,
      Selected_Style,
      Accent_Style);

   type Tone is
     (Default_Tone,
      Accent_Tone,
      Positive_Tone,
      Negative_Tone,
      Warning_Tone);

   type Emphasis is
     (Normal_Emphasis,
      Bold_Emphasis,
      Dim_Emphasis,
      Selected_Emphasis);

   type Style_Description is record
      Text_Tone : Tone;
      Weight    : Emphasis;
   end record;

   function For_Amount (Value : Long_Long_Integer) return Semantic_Style is
     (if Value < 0 then Negative_Style
      elsif Value > 0 then Positive_Style
      else Plain_Style);

   function Describe (Style : Semantic_Style) return Style_Description;

   procedure Initialize;

   procedure Apply (Style : Semantic_Style);

   procedure Reset;

   function Colors_Available return Boolean;

end HRA_N.UI.Terminal_Style;
