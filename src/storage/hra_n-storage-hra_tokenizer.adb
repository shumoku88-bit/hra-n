-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.HRA_Tokenizer
-------------------------------------------------------------------------------

package body HRA_N.Storage.HRA_Tokenizer is

   procedure Tokenize_Line
     (Line   : String;
      Tokens : out Token_Array;
      Count  : out Natural)
   is
      Idx : Positive := Line'First;

      function Is_Space (C : Character) return Boolean is
        (C = ' ' or else C = ASCII.HT or else C = ASCII.CR or else C = ASCII.LF);

   begin
      Count := 0;

      while Idx <= Line'Last loop
         --  Skip leading whitespace
         while Idx <= Line'Last and then Is_Space (Line (Idx)) loop
            Idx := Idx + 1;
         end loop;

         exit when Idx > Line'Last;

         --  Check for comment start
         if Line (Idx) = '#' then
            exit;
         end if;

         --  Found next token
         if Count >= Max_Line_Tokens then
            exit;
         end if;

         Count := Count + 1;

         if Line (Idx) = '"' then
            --  Quoted string
            Tokens (Count).Kind := Tok_Quoted;
            Idx := Idx + 1;
            Tokens (Count).First := Idx;

            while Idx <= Line'Last and then Line (Idx) /= '"' loop
               Idx := Idx + 1;
            end loop;

            Tokens (Count).Last := Idx - 1;
            if Idx <= Line'Last and then Line (Idx) = '"' then
               Idx := Idx + 1;
            end if;
         else
            --  Regular word
            Tokens (Count).Kind := Tok_Word;
            Tokens (Count).First := Idx;

            while Idx <= Line'Last and then not Is_Space (Line (Idx)) loop
               Idx := Idx + 1;
            end loop;

            Tokens (Count).Last := Idx - 1;
         end if;
      end loop;
   end Tokenize_Line;

end HRA_N.Storage.HRA_Tokenizer;
