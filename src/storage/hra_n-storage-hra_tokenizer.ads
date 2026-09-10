-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.HRA_Tokenizer
--
--  Tokenizer for canonical .hra file formats (journal.hra, scheduled.hra, policy.hra).
--  Extracts whitespace-separated tokens and quoted string literals.
--  Ignores comments (#) and blank lines.
-------------------------------------------------------------------------------

package HRA_N.Storage.HRA_Tokenizer is

   Max_Line_Tokens : constant := 64;

   type Token_Kind is (Tok_Word, Tok_Quoted);

   type HRA_Token is record
      Kind  : Token_Kind := Tok_Word;
      First : Positive   := 1;
      Last  : Natural    := 0;
   end record;

   type Token_Array is array (1 .. Max_Line_Tokens) of HRA_Token;

   procedure Tokenize_Line
     (Line   : String;
      Tokens : out Token_Array;
      Count  : out Natural);

   --  Helper to extract slice from line
   function Slice (Line : String; Tok : HRA_Token) return String is
     (if Tok.Last >= Tok.First then Line (Tok.First .. Tok.Last) else "");

end HRA_N.Storage.HRA_Tokenizer;
