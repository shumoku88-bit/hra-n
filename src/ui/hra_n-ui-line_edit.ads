-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Line_Edit
--
--  Minimal curses line editor shared by the keyboard TUI intent editors.
--  Editors own drafts only: cancellation produces no retained fact.
-------------------------------------------------------------------------------

package HRA_N.UI.Line_Edit is

   --  Edit one line on Prompt_Row with an initial value. The input buffer
   --  is Result'Range: longer entries stop at the caller's bound. Echoes
   --  input, accepts on Enter, cancels on Esc. A blank result is returned
   --  only when Allow_Blank holds or the user cancels (Cancelled).
   procedure Edit_Line
     (Prompt_Row   : Natural;
      Prompt_Text  : String;
      Initial      : String;
      Allow_Blank  : Boolean;
      Result       : out String;
      Result_Len   : out Natural;
      Cancelled    : out Boolean);

   --  Edit_Line returning a fresh string bounded by Max_Length; empty on
   --  cancel or blank input.
   function Prompt_For
     (Prompt_Row  : Natural;
      Prompt_Text : String;
      Initial     : String := "";
      Allow_Blank : Boolean := False;
      Max_Length  : Positive := 96) return String;

   --  Blocking confirm row. Returns True only on an explicit y/Y answer.
   function Confirm (Prompt_Row : Natural; Prompt_Text : String) return Boolean;

   --  Blocking notice row dismissed by any key.
   procedure Wait_Key (Prompt_Row : Natural; Prompt_Text : String);

end HRA_N.UI.Line_Edit;
