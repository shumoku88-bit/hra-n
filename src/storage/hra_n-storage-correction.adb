with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Storage.Text_Fields; use HRA_N.Storage.Text_Fields;

package body HRA_N.Storage.Correction is
   Header : constant String := "LOAM-EVENT-CORRECTION-MEMORY" & ASCII.HT & "1";
   function Error
     (R : in out Read_Result; Line : Natural; Msg : String) return Read_Result is
   begin
      R.Success := False; R.Error_Line := Line;
      R.Error_Len := Natural'Min (Msg'Length, R.Error_Reason'Length);
      R.Error_Reason (1 .. R.Error_Len) := Msg (Msg'First .. Msg'First + R.Error_Len - 1);
      return R;
   end Error;
   function Valid (S : String) return Boolean is
     (S'Length in 1 .. Max_Token_Length);

   function Read_File (Path : String) return Read_Result is
      R : Read_Result; F : File_Type; Fields : Field_Array; Count : Natural;
      Line_No : Natural := 1;
   begin
      begin Open (F, In_File, Path); exception when others => return Error (R, 0, "Cannot open correction file"); end;
      if End_Of_File (F) or else Get_Line (F) /= Header then
         Close (F); return Error (R, 1, "Invalid correction header");
      end if;
      while not End_Of_File (F) loop
         Line_No := Line_No + 1;
         declare Line : constant String := Get_Line (F); begin
            if Line'Length > 0 then
               Split_Tabs (Line, Fields, Count);
               if Count /= 4 then Close (F); return Error (R, Line_No, "Malformed CORRECTION row"); end if;
               declare
                  Tag : constant String := Line (Fields (1).First .. Fields (1).Last);
                  Id : constant String := Line (Fields (2).First .. Fields (2).Last);
                  Target : constant String := Line (Fields (3).First .. Fields (3).Last);
                  Replacement : constant String := Line (Fields (4).First .. Fields (4).Last);
               begin
                  if Tag /= "CORRECTION" or else not Valid (Id) or else not Valid (Target)
                    or else not Valid (Replacement) or else R.Memory.Count = Max_Corrections
                  then Close (F); return Error (R, Line_No, "Invalid correction evidence"); end if;
                  R.Memory.Count := R.Memory.Count + 1;
                  R.Memory.Values (R.Memory.Count) :=
                    (Id => (Token => Make_Token (Id)), Target => (Token => Make_Token (Target)),
                     Replacement => (Token => Make_Token (Replacement)));
                  if not Ids_Are_Unique (R.Memory) then
                     Close (F); return Error (R, Line_No, "Duplicate correction identity");
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (F); R.Success := True; return R;
   end Read_File;

   function Encode (Memory : Correction_Memory) return String is
      Text : Unbounded_String := To_Unbounded_String (Header & ASCII.LF);
   begin
      for I in 1 .. Memory.Count loop
         declare C : constant Event_Correction := Memory.Values (I); begin
            Append (Text, "CORRECTION" & ASCII.HT &
              C.Id.Token.Value (1 .. C.Id.Token.Length) & ASCII.HT &
              C.Target.Token.Value (1 .. C.Target.Token.Length) & ASCII.HT &
              C.Replacement.Token.Value (1 .. C.Replacement.Token.Length) & ASCII.LF);
         end;
      end loop;
      return To_String (Text);
   end Encode;
end HRA_N.Storage.Correction;
