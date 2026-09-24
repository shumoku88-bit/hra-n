with Ada.Directories;
with Ada.Strings.Unbounded;
with HRA_N.Storage.Exact_File;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Description; use HRA_N.Core.Description;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Attention; use HRA_N.Core.Attention;

package body HRA_N.Storage.Loam_Attention_Reader is
   package US renames Ada.Strings.Unbounded;
   Header : constant String := "LOAM-ATTENTION-MEMORY" & ASCII.HT & "1";

   function Read_Content (Content : String) return Read_Result is
      Result : Read_Result;
      Pos : Natural := Content'First;
      Line_No : Natural := 0;

      function Fail (Message : String) return Read_Result is
         N : constant Natural := Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Success := False;
         Result.Diagnostic_Len := N;
         Result.Diagnostic (1 .. N) := Message (Message'First .. Message'First + N - 1);
         return Result;
      end Fail;

      function Valid_Id (S : String) return Boolean is
      begin
         if S'Length = 0 or else S'Length > Max_Token_Length then
            return False;
         end if;
         for C of S loop
            if C = ASCII.HT or else C = ASCII.CR or else C = ASCII.LF then
               return False;
            end if;
         end loop;
         return True;
      end Valid_Id;

      function Decode (S : String; Text : out Description_Text) return Boolean is
         Buffer : String (1 .. Max_Description_Length);
         N : Natural := 0;
         I : Integer := S'First;
         C : Character;
      begin
         while I <= S'Last loop
            C := S (I);
            if C = '\' then
               if I = S'Last then
                  return False;
               end if;
               I := I + 1;
               case S (I) is
                  when '\' => C := '\';
                  when 'n' => C := ASCII.LF;
                  when 'r' => C := ASCII.CR;
                  when 't' => C := ASCII.HT;
                  when others => return False;
               end case;
            end if;
            if N = Max_Description_Length then
               return False;
            end if;
            N := N + 1;
            Buffer (N) := C;
            I := I + 1;
         end loop;
         Text := Make_Description (Buffer (1 .. N));
         return True;
      end Decode;
   begin
      Result.Present := True;
      if Content'Length = 0 or else Content (Content'Last) /= ASCII.LF then
         return Fail ("Attention frame requires a trailing newline");
      end if;
      while Pos <= Content'Last loop
         declare
            Last : Natural := Pos;
         begin
            while Last <= Content'Last and then Content (Last) /= ASCII.LF loop
               Last := Last + 1;
            end loop;
            Line_No := Line_No + 1;
            declare
               Line : constant String := Content (Pos .. Last - 1);
               --  Preserve empty fields and reject any extra tab.
               Start : Natural := Line'First;
               Fields : array (1 .. 5) of US.Unbounded_String :=
                 [others => US.Null_Unbounded_String];
               Count : Natural := 0;
            begin
               if Line_No = 1 then
                  if Line /= Header then
                     return Fail ("unsupported Attention header");
                  end if;
               else
                  for J in Line'Range loop
                     if Line (J) = ASCII.HT then
                        Count := Count + 1;
                        if Count > 5 then
                           return Fail ("Attention row arity");
                        end if;
                        Fields (Count) := US.To_Unbounded_String (Line (Start .. J - 1));
                        Start := J + 1;
                     end if;
                  end loop;
                  Count := Count + 1;
                  if Count > 5 then
                     return Fail ("Attention row arity");
                  end if;
                  Fields (Count) := US.To_Unbounded_String (Line (Start .. Line'Last));
                  declare
                     Tag : constant String := US.To_String (Fields (1));
                     Id : constant String := US.To_String (Fields (2));
                     Date_Text : constant String := US.To_String (Fields (4));
                     Date_Value : Date_Type;
                     Context : Description_Text;
                     Due : Attention_Due;
                  begin
                     if not Valid_Id (Id) then
                        return Fail ("invalid Attention id");
                     end if;
                     if Tag = "ITEM" then
                        if Count /= 5 or else Result.Memory.Item_Count = Max_Attention_Items then
                           return Fail ("Attention item arity or capacity");
                        end if;
                        if not Decode (US.To_String (Fields (5)), Context) then
                           return Fail ("invalid or oversized Attention context escape");
                        end if;
                        declare
                           Kind : constant String := US.To_String (Fields (3));
                        begin
                           if Kind = "DUE_ON" and then Parse_Iso_Date (Date_Text, Date_Value) then
                              Due := (Kind => Due_On_Date, Due_Date => Date_Value);
                           elsif Kind = "NO_DUE_DATE" and then Date_Text = "-" then
                              Due := (Kind => No_Due_Date);
                           elsif Kind = "DUE_UNDETERMINED" and then Date_Text = "-" then
                              Due := (Kind => Due_Undetermined);
                           else
                              return Fail ("invalid Attention due kind or date");
                           end if;
                        end;
                        Result.Memory.Item_Count := Result.Memory.Item_Count + 1;
                        Result.Memory.Items (Result.Memory.Item_Count) :=
                          (Id => Make_Token (Id), Context => Context, Due => Due);
                     elsif Tag = "CLOSE" then
                        if Count /= 4 or else Result.Memory.Close_Count = Max_Attention_Items then
                           return Fail ("Attention closure arity or capacity");
                        end if;
                        if not Parse_Iso_Date (US.To_String (Fields (3)), Date_Value) then
                           return Fail ("invalid Attention closure date");
                        end if;
                        declare
                           Kind : constant String := US.To_String (Fields (4));
                        begin
                           if Kind /= "RESOLVED" and then Kind /= "DROPPED" then
                              return Fail ("invalid Attention closure kind");
                           end if;
                           Result.Memory.Close_Count := Result.Memory.Close_Count + 1;
                           Result.Memory.Closures (Result.Memory.Close_Count) :=
                             (Target => Make_Token (Id), Known_On => Date_Value,
                              Kind => (if Kind = "RESOLVED" then Closure_Resolved else Closure_Dropped));
                        end;
                     else
                        return Fail ("unknown Attention row");
                     end if;
                  end;
               end if;
            end;
            Pos := Last + 1;
         end;
      end loop;
      if not Item_Ids_Are_Unique (Result.Memory)
        or else not Closure_References_Are_Closed (Result.Memory)
        or else not Closures_Are_One_To_One (Result.Memory)
      then
         return Fail ("Attention identity or closure conflict");
      end if;
      Result.Success := True;
      return Result;
   exception
      when others => return Fail ("unexpected Attention reader failure");
   end Read_Content;

   function Read_File (Path : String) return Read_Result is
      Result : Read_Result;
   begin
      if not Ada.Directories.Exists (Path) then
         Result.Success := True;
         return Result;
      end if;
      declare
         Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Path);
      begin
         if Exact.Success then
            return Read_Content (US.To_String (Exact.Content));
         end if;
      end;
      Result.Present := True;
      Result.Diagnostic_Len := 28;
      Result.Diagnostic (1 .. Result.Diagnostic_Len) := "cannot read Attention source";
      return Result;
   exception
      when others =>
         Result.Diagnostic_Len := 29;
         Result.Diagnostic (1 .. Result.Diagnostic_Len) := "cannot probe Attention source";
         return Result;
   end Read_File;
end HRA_N.Storage.Loam_Attention_Reader;
