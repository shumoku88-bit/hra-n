with Ada.Directories;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata;
use HRA_N.Core.Transaction_Metadata;

package body HRA_N.Application.Canonical_Balance_Query is

   function Row_Less (Left, Right : Coordinate_Row) return Boolean is
      Left_Locus  : constant String :=
        Left.Locus.Value (1 .. Left.Locus.Length);
      Right_Locus : constant String :=
        Right.Locus.Value (1 .. Right.Locus.Length);
      Left_Measure  : constant String :=
        Left.Measure.Value (1 .. Left.Measure.Length);
      Right_Measure : constant String :=
        Right.Measure.Value (1 .. Right.Measure.Length);
   begin
      if Left_Locus /= Right_Locus then
         return Left_Locus < Right_Locus;
      end if;
      return Left_Measure < Right_Measure;
   end Row_Less;

   function Can_Add
     (Left, Right : Long_Long_Integer) return Boolean
   is
   begin
      if Right > 0 then
         return Left <= Long_Long_Integer'Last - Right;
      elsif Right < 0 then
         return Left >= Long_Long_Integer'First - Right;
      else
         return True;
      end if;
   end Can_Add;

   function Project
     (Actual : HRA_N.Storage.Loam_Actual_Reader.Loam_Actual_Result)
      return Balance_View
   is
      Result : Balance_View;

      procedure Fail (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Success := False;
         Result.Diagnostic := [others => ' '];
         Result.Diagnostic_Len := Len;
         if Len > 0 then
            Result.Diagnostic (1 .. Len) :=
              Message (Message'First .. Message'First + Len - 1);
         end if;
      end Fail;

      function Find_Row
        (Locus, Measure : Token_Text) return Natural
      is
      begin
         for I in 1 .. Result.Count loop
            if Equal_Token (Result.Rows (I).Locus, Locus)
              and then Equal_Token (Result.Rows (I).Measure, Measure)
            then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Row;

      procedure Add_Effect
        (Item : Effect;
         Ok   : out Boolean)
      is
         Position : Natural :=
           Find_Row (Item.Locus.Token, Item.Measure.Token);
         Delta : constant Long_Long_Integer :=
           Long_Long_Integer (Item.Amount.Quanta);
      begin
         Ok := False;

         if Position = 0 then
            if Result.Count = Max_Rows then
               Fail ("canonical balance coordinate limit exceeded");
               return;
            end if;
            Result.Count := Result.Count + 1;
            Position := Result.Count;
            Result.Rows (Position).Locus := Item.Locus.Token;
            Result.Rows (Position).Measure := Item.Measure.Token;
         end if;

         if not Can_Add (Result.Rows (Position).Net, Delta) then
            Fail ("canonical balance net accumulation overflow");
            return;
         end if;

         if Delta > 0 then
            if not Can_Add (Result.Rows (Position).Inflow, Delta) then
               Fail ("canonical balance inflow accumulation overflow");
               return;
            end if;
            Result.Rows (Position).Inflow :=
              Result.Rows (Position).Inflow + Delta;
         elsif Delta < 0 then
            declare
               Magnitude : constant Long_Long_Integer := -Delta;
            begin
               if not Can_Add
                 (Result.Rows (Position).Outflow, Magnitude)
               then
                  Fail ("canonical balance outflow accumulation overflow");
                  return;
               end if;
               Result.Rows (Position).Outflow :=
                 Result.Rows (Position).Outflow + Magnitude;
            end;
         end if;

         Result.Rows (Position).Net :=
           Result.Rows (Position).Net + Delta;
         Result.Rows (Position).Posting_Count :=
           Result.Rows (Position).Posting_Count + 1;
         Ok := True;
      end Add_Effect;

   begin
      if not Actual.Success then
         if Actual.Error_Len > 0 then
            Fail
              ("cannot admit canonical actual.loam: "
               & Actual.Error_Reason (1 .. Actual.Error_Len));
         else
            Fail ("cannot admit canonical actual.loam");
         end if;
         return Result;
      end if;

      Result.Physical_Event_Count := Natural (Actual.Events.Length);

      for Position in 1 .. Natural (Actual.Events.Length) loop
         declare
            Ev : constant Event :=
              Actual.Events.Element (Positive (Position));
            Successor : Event_Id;
            Is_Superseded : Boolean := False;
         begin
            Find_Successor
              (Actual.Metadata, Id (Ev), Successor, Is_Superseded);

            if Is_Superseded then
               Result.Superseded_Event_Count :=
                 Result.Superseded_Event_Count + 1;
            else
               Result.Active_Event_Count :=
                 Result.Active_Event_Count + 1;

               for I in 1 .. Effect_Count (Ev) loop
                  declare
                     Ok : Boolean;
                  begin
                     Add_Effect (Effect_At (Ev, I), Ok);
                     if not Ok then
                        return Result;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      --  Stable lexical order makes GUI/table presentation deterministic
      --  without assigning accounting meaning to a coordinate.
      for I in 2 .. Result.Count loop
         declare
            Key : constant Coordinate_Row := Result.Rows (I);
            J   : Natural := I - 1;
         begin
            while J > 0 and then Row_Less (Key, Result.Rows (J)) loop
               Result.Rows (J + 1) := Result.Rows (J);
               J := J - 1;
            end loop;
            Result.Rows (J + 1) := Key;
         end;
      end loop;

      Result.Success := True;
      Result.Diagnostic_Len := 0;
      return Result;
   end Project;

   function Execute (Root_Path : String) return Balance_View is
      Actual_Path : constant String :=
        Ada.Directories.Compose (Root_Path, "actual.loam");
   begin
      if Root_Path'Length = 0 then
         declare
            Result  : Balance_View;
            Message : constant String :=
              "canonical data root must not be empty";
         begin
            Result.Diagnostic_Len := Message'Length;
            Result.Diagnostic (1 .. Message'Length) := Message;
            return Result;
         end;
      end if;

      return Project
        (HRA_N.Storage.Loam_Actual_Reader.Read_Loam_Actual_File
           (Actual_Path));
   end Execute;

end HRA_N.Application.Canonical_Balance_Query;
