-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Core.Validity
-------------------------------------------------------------------------------

package body HRA_N.Core.Validity with
  SPARK_Mode => On
is

   function Make_Date
     (Year  : Year_Type;
      Month : Month_Type;
      Day   : Day_Type) return Date_Type
   is
   begin
      return (Year => Year, Month => Month, Day => Day);
   end Make_Date;

   function Format_Iso_Date (D : Date_Type) return Iso_Date_String is
      Result : Iso_Date_String := "0000-00-00";
      Y      : constant Year_Type  := D.Year;
      M      : constant Month_Type := D.Month;
      Day_V  : constant Day_Type   := D.Day;
   begin
      Result (1)  := Character'Val (Character'Pos ('0') + (Y / 1000));
      Result (2)  := Character'Val (Character'Pos ('0') + ((Y / 100) mod 10));
      Result (3)  := Character'Val (Character'Pos ('0') + ((Y / 10) mod 10));
      Result (4)  := Character'Val (Character'Pos ('0') + (Y mod 10));
      Result (5)  := '-';
      Result (6)  := Character'Val (Character'Pos ('0') + (M / 10));
      Result (7)  := Character'Val (Character'Pos ('0') + (M mod 10));
      Result (8)  := '-';
      Result (9)  := Character'Val (Character'Pos ('0') + (Day_V / 10));
      Result (10) := Character'Val (Character'Pos ('0') + (Day_V mod 10));
      return Result;
   end Format_Iso_Date;

   function Previous_Days_7 (Ending : Date_Type) return Week_Days_Array is
      D7 : constant Date_Type := Ending;
      D6 : constant Date_Type := Prev_Day (D7);
      D5 : constant Date_Type := Prev_Day (D6);
      D4 : constant Date_Type := Prev_Day (D5);
      D3 : constant Date_Type := Prev_Day (D4);
      D2 : constant Date_Type := Prev_Day (D3);
      D1 : constant Date_Type := Prev_Day (D2);
   begin
      return [D1, D2, D3, D4, D5, D6, D7];
   end Previous_Days_7;

   function Make_Validity_Memory
     (Entries : Validity_Entry_List) return Validity_Memory
   is
   begin
      return (Entries => Entries);
   end Make_Validity_Memory;

   procedure Find_Occurrence_Date
     (Memory : in  Validity_Memory;
      Ev_Id  : in  Types.Event_Id;
      Date   : out Date_Type;
      Found  : out Boolean)
   is
   begin
      for I in 1 .. Memory.Entries.Count loop
         if Equal_Token (Memory.Entries.Values (I).Event_Id.Token, Ev_Id.Token) then
            Date  := Memory.Entries.Values (I).Valid_On;
            Found := True;
            return;
         end if;
      end loop;
      Date  := (Year => 2026, Month => 1, Day => 1);
      Found := False;
   end Find_Occurrence_Date;

   function Root_Fact_Id (Ev_Id : Event_Id) return Validity_Fact_Id is
      Sched_Pre : constant String := "scheduled-completion:";
      Val_Pre   : constant String := "scheduled-completion-validity:";
      Root_Pre  : constant String := "event-root:";
      L         : constant Natural := Ev_Id.Token.Length;
   begin
      if L >= Sched_Pre'Length
        and then Ev_Id.Token.Value (1 .. Sched_Pre'Length) = Sched_Pre
      then
         declare
            Suffix_Len : constant Natural := L - Sched_Pre'Length;
            Result_Len : constant Natural := Val_Pre'Length + Suffix_Len;
            Buf        : String (1 .. Max_Token_Length) := [others => ' '];
            Copy_Len   : constant Natural := Natural'Min (Result_Len, Max_Token_Length);
         begin
            Buf (1 .. Val_Pre'Length) := Val_Pre;
            if Suffix_Len > 0 and then Val_Pre'Length < Max_Token_Length then
               declare
                  Avail : constant Natural := Max_Token_Length - Val_Pre'Length;
                  Take  : constant Natural := Natural'Min (Suffix_Len, Avail);
               begin
                  Buf (Val_Pre'Length + 1 .. Val_Pre'Length + Take) :=
                    Ev_Id.Token.Value (Sched_Pre'Length + 1 .. Sched_Pre'Length + Take);
               end;
            end if;
            return (Token => (Length => Copy_Len, Value => Buf));
         end;
      else
         declare
            Result_Len : constant Natural := Root_Pre'Length + L;
            Buf        : String (1 .. Max_Token_Length) := [others => ' '];
            Copy_Len   : constant Natural := Natural'Min (Result_Len, Max_Token_Length);
         begin
            Buf (1 .. Root_Pre'Length) := Root_Pre;
            if L > 0 and then Root_Pre'Length < Max_Token_Length then
               declare
                  Avail : constant Natural := Max_Token_Length - Root_Pre'Length;
                  Take  : constant Natural := Natural'Min (L, Avail);
               begin
                  Buf (Root_Pre'Length + 1 .. Root_Pre'Length + Take) :=
                    Ev_Id.Token.Value (1 .. Take);
               end;
            end if;
            return (Token => (Length => Copy_Len, Value => Buf));
         end;
      end if;
   end Root_Fact_Id;

   function Is_Root_Fact (Fact : Validity_Fact) return Boolean is
     (Equal_Token (Fact.Id.Token, Root_Fact_Id (Fact.Event_Id).Token));

   procedure Find_Fact_By_Id
     (History : in  Validity_History;
      Id      : in  Validity_Fact_Id;
      Fact    : out Validity_Fact;
      Found   : out Boolean)
   is
   begin
      for I in 1 .. History.Fact_Count loop
         if Equal_Token (History.Facts (I).Id.Token, Id.Token) then
            Fact  := History.Facts (I);
            Found := True;
            return;
         end if;
      end loop;
      Fact  := (Id       => (Token => (Length => 0, Value => [others => ' '])),
                Event_Id => (Token => (Length => 0, Value => [others => ' '])),
                Valid_On => (Year => 2026, Month => 1, Day => 1));
      Found := False;
   end Find_Fact_By_Id;

   procedure Find_Correction_By_Id
     (History : in  Validity_History;
      Id      : in  Validity_Correction_Id;
      Corr    : out Validity_Correction;
      Found   : out Boolean)
   is
   begin
      for I in 1 .. History.Correction_Count loop
         if Equal_Token (History.Corrections (I).Id.Token, Id.Token) then
            Corr  := History.Corrections (I);
            Found := True;
            return;
         end if;
      end loop;
      Corr  := (Id          => (Token => (Length => 0, Value => [others => ' '])),
                Target      => (Token => (Length => 0, Value => [others => ' '])),
                Replacement => (Token => (Length => 0, Value => [others => ' '])));
      Found := False;
   end Find_Correction_By_Id;

end HRA_N.Core.Validity;
