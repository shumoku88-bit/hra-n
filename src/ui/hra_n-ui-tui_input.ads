-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package spec: HRA_N.UI.TUI_Input
-------------------------------------------------------------------------------

package HRA_N.UI.TUI_Input is

   type Event_Kind is (Key_Input, Scroll_Input, Ignored_Input);
   type Scroll_Direction is (Scroll_Up, Scroll_Down);

   type Event (Kind : Event_Kind := Ignored_Input) is record
      case Kind is
         when Key_Input =>
            Key_Code : Integer;
         when Scroll_Input =>
            Direction : Scroll_Direction;
         when Ignored_Input =>
            null;
      end case;
   end record;

   procedure Start_Mouse_Scroll;
   procedure Stop_Mouse_Scroll;

   function Read return Event;

   function Is_Up (Key : Integer) return Boolean;
   function Is_Down (Key : Integer) return Boolean;
   function Is_Left (Key : Integer) return Boolean;
   function Is_Right (Key : Integer) return Boolean;
   function Is_Quit (Key : Integer) return Boolean;
   function Is_Redraw (Key : Integer) return Boolean;
   function Is_Enter (Key : Integer) return Boolean;

end HRA_N.UI.TUI_Input;
