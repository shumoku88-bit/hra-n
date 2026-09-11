-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Terminal_Style
-------------------------------------------------------------------------------

with Terminal_Interface.Curses;

package body HRA_N.UI.Terminal_Style is

   package Curses renames Terminal_Interface.Curses;

   Accent_Pair   : constant Curses.Redefinable_Color_Pair := 1;
   Positive_Pair : constant Curses.Redefinable_Color_Pair := 2;
   Negative_Pair : constant Curses.Redefinable_Color_Pair := 3;
   Warning_Pair  : constant Curses.Redefinable_Color_Pair := 4;

   Colors_Ready : Boolean := False;

   function Describe (Style : Semantic_Style) return Style_Description is
   begin
      case Style is
         when Plain_Style =>
            return (Text_Tone => Default_Tone, Weight => Normal_Emphasis);
         when Header_Style =>
            return (Text_Tone => Accent_Tone, Weight => Bold_Emphasis);
         when Muted_Style =>
            return (Text_Tone => Default_Tone, Weight => Dim_Emphasis);
         when Positive_Style =>
            return (Text_Tone => Positive_Tone, Weight => Normal_Emphasis);
         when Negative_Style =>
            return (Text_Tone => Negative_Tone, Weight => Normal_Emphasis);
         when Warning_Style =>
            return (Text_Tone => Warning_Tone, Weight => Bold_Emphasis);
         when Error_Style =>
            return (Text_Tone => Negative_Tone, Weight => Bold_Emphasis);
         when Selected_Style =>
            return (Text_Tone => Accent_Tone, Weight => Selected_Emphasis);
         when Accent_Style =>
            return (Text_Tone => Accent_Tone, Weight => Normal_Emphasis);
      end case;
   end Describe;

   function Attributes_For
     (Weight : Emphasis) return Curses.Character_Attribute_Set
   is
   begin
      case Weight is
         when Normal_Emphasis =>
            return Curses.Normal_Video;
         when Bold_Emphasis =>
            return (Bold_Character => True, others => False);
         when Dim_Emphasis =>
            return (Dim_Character => True, others => False);
         when Selected_Emphasis =>
            return
              (Reverse_Video  => True,
               Bold_Character => True,
               others         => False);
      end case;
   end Attributes_For;

   function Pair_For (Text_Tone : Tone) return Curses.Color_Pair is
   begin
      if not Colors_Ready then
         return Curses.Color_Pair'First;
      end if;

      case Text_Tone is
         when Default_Tone =>
            return Curses.Color_Pair'First;
         when Accent_Tone =>
            return Curses.Color_Pair (Accent_Pair);
         when Positive_Tone =>
            return Curses.Color_Pair (Positive_Pair);
         when Negative_Tone =>
            return Curses.Color_Pair (Negative_Pair);
         when Warning_Tone =>
            return Curses.Color_Pair (Warning_Pair);
      end case;
   end Pair_For;

   procedure Initialize is
      Background : Curses.Color_Number := Curses.Black;
   begin
      Colors_Ready := False;

      if not Curses.Has_Colors then
         return;
      end if;

      Curses.Start_Color;

      begin
         Curses.Use_Default_Colors;
         Background := Curses.Default_Color;
      exception
         when Curses.Curses_Exception =>
            Background := Curses.Black;
      end;

      Curses.Init_Pair (Accent_Pair, Curses.Cyan, Background);
      Curses.Init_Pair (Positive_Pair, Curses.Green, Background);
      Curses.Init_Pair (Negative_Pair, Curses.Red, Background);
      Curses.Init_Pair (Warning_Pair, Curses.Yellow, Background);
      Colors_Ready := True;
   exception
      when Curses.Curses_Exception =>
         Colors_Ready := False;
   end Initialize;

   procedure Apply (Style : Semantic_Style) is
      Description : constant Style_Description := Describe (Style);
   begin
      Curses.Set_Character_Attributes
        (Win   => Curses.Standard_Window,
         Attr  => Attributes_For (Description.Weight),
         Color => Pair_For (Description.Text_Tone));
   end Apply;

   procedure Reset is
   begin
      Curses.Set_Character_Attributes
        (Win   => Curses.Standard_Window,
         Attr  => Curses.Normal_Video,
         Color => Curses.Color_Pair'First);
   end Reset;

   function Colors_Available return Boolean is (Colors_Ready);

end HRA_N.UI.Terminal_Style;
