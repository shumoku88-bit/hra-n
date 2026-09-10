-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.UI.Prompt
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.UI.Output;   use HRA_N.UI.Output;

package body HRA_N.UI.Prompt is

   function Format_Date (D : Date_Type) return String is
      Y_Str : constant String := Trim (D.Year'Image, Ada.Strings.Both);
      M_Str : constant String := (if D.Month < 10 then "0" else "") & Trim (D.Month'Image, Ada.Strings.Both);
      D_Str : constant String := (if D.Day < 10 then "0" else "") & Trim (D.Day'Image, Ada.Strings.Both);
   begin
      return Y_Str & "-" & M_Str & "-" & D_Str;
   end Format_Date;

   function Prompt_Line (Prompt_Text : String) return String is
      Buffer : String (1 .. 1024);
      Last   : Natural := 0;
   begin
      Put (Prompt_Text);
      Ada.Text_IO.Get_Line (Buffer, Last);
      return Trim (Buffer (1 .. Last), Ada.Strings.Both);
   exception
      when Ada.IO_Exceptions.End_Error =>
         New_Line;
         return "";
   end Prompt_Line;

   function Prompt_String
     (Prompt_Text : String;
      Default     : String := "";
      Required    : Boolean := True) return String
   is
      Full_Prompt : constant String :=
        (if Default'Length > 0 then Prompt_Text & " [" & Default & "]: " else Prompt_Text & ": ");
   begin
      loop
         declare
            Input : constant String := Prompt_Line (Full_Prompt);
         begin
            if Input'Length > 0 then
               return Input;
            elsif Default'Length > 0 then
               return Default;
            elsif not Required then
               return "";
            else
               Put_Line ("  [!] Value cannot be empty.");
            end if;
         end;
      end loop;
   end Prompt_String;

   function Prompt_Date
     (Prompt_Text : String;
      Default     : Date_Type) return Date_Type
   is
      Def_Str     : constant String := Format_Date (Default);
      Full_Prompt : constant String := Prompt_Text & " [" & Def_Str & "]: ";
   begin
      loop
         declare
            Input : constant String := Prompt_Line (Full_Prompt);
            Parsed : Date_Type;
         begin
            if Input'Length = 0 then
               return Default;
            elsif Parse_Iso_Date (Input, Parsed) then
               return Parsed;
            else
               Put_Line ("  [!] Invalid ISO calendar date. Must be real YYYY-MM-DD.");
            end if;
         end;
      end loop;
   end Prompt_Date;

   function Prompt_Quanta
     (Prompt_Text : String;
      Measure_Str : String := "jpy";
      Min_Val     : Quanta_Type := 1) return Quanta_Type
   is
      Full_Prompt : constant String := Prompt_Text & " (" & Measure_Str & "): ";
   begin
      loop
         declare
            Input : constant String := Prompt_Line (Full_Prompt);
         begin
            if Input'Length = 0 then
               Put_Line ("  [!] Amount is required.");
            else
               begin
                  declare
                     Val : constant Quanta_Type := Quanta_Type'Value (Input);
                  begin
                     if Val >= Min_Val then
                        return Val;
                     else
                        Put_Line ("  [!] Amount must be at least" & Quanta_Type'Image (Min_Val) & ".");
                     end if;
                  end;
               exception
                  when others =>
                     Put_Line ("  [!] Invalid integer amount.");
               end;
            end if;
         end;
      end loop;
   end Prompt_Quanta;

   procedure Display_Admitted_Loci (Vocab : Locus_Vocabulary) is
   begin
      Put_Line ("  Admitted loci (" & Trim (Vocab.Count'Image, Ada.Strings.Both) & "):");
      for I in 1 .. Vocab.Count loop
         declare
            Tok : constant Token_Text := Vocab.Values (I).Token;
         begin
            Put_Line ("    - " & Tok.Value (1 .. Tok.Length));
         end;
      end loop;
   end Display_Admitted_Loci;

   function Prompt_Locus
     (Prompt_Text : String;
      Vocab       : Locus_Vocabulary;
      Disallow    : String := "") return String
   is
      Full_Prompt : constant String := Prompt_Text & " (or '?' to list): ";
   begin
      loop
         declare
            Input : constant String := Prompt_Line (Full_Prompt);
         begin
            if Input = "?" then
               Display_Admitted_Loci (Vocab);
            elsif Input'Length = 0 then
               Put_Line ("  [!] Locus cannot be empty.");
            elsif Disallow'Length > 0 and then Input = Disallow then
               Put_Line ("  [!] Destination locus must differ from source locus.");
            else
               declare
                  Tok : constant Locus_Id := (Token => Make_Token (Input));
               begin
                  if Admits_Locus (Vocab, Tok) then
                     return Input;
                  else
                     Put_Line ("  [!] Locus '" & Input & "' is not admitted by authority.");
                  end if;
               end;
            end if;
         end;
      end loop;
   end Prompt_Locus;

end HRA_N.UI.Prompt;
