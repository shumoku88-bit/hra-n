-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Prompt
--
--  Consolidated terminal interactive prompt helpers.
--  Encapsulates EOF handling, whitespace trimming, date parsing,
--  positive quanta validation, and locus vocabulary admission checks.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;     use HRA_N.Core.Types;
with HRA_N.Core.Validity;  use HRA_N.Core.Validity;
with HRA_N.Core.Admission; use HRA_N.Core.Admission;

package HRA_N.UI.Prompt is

   --  Raw line input with whitespace trimming and EOF safety.
   function Prompt_Line (Prompt_Text : String) return String;

   --  Prompt for a string with an optional default value.
   --  If Required is True, loops until non-empty input is received.
   function Prompt_String
     (Prompt_Text : String;
      Default     : String := "";
      Required    : Boolean := True) return String;

   --  Prompt for a valid ISO calendar date with a default value.
   --  Loops until a valid, real calendar date (YYYY-MM-DD) is entered.
   function Prompt_Date
     (Prompt_Text : String;
      Default     : Date_Type) return Date_Type;

   --  Prompt for a positive quanta integer amount (> 0).
   --  Loops until valid integer is entered.
   function Prompt_Quanta
     (Prompt_Text : String;
      Measure_Str : String := "jpy";
      Min_Val     : Quanta_Type := 1) return Quanta_Type;

   --  Prompt for an admitted locus. Supports '?' to display vocabulary.
   --  Optionally rejects Disallow (e.g. source locus when prompting destination).
   function Prompt_Locus
     (Prompt_Text : String;
      Vocab       : Locus_Vocabulary;
      Disallow    : String := "") return String;

end HRA_N.UI.Prompt;
