-------------------------------------------------------------------------------
--  HRA-N: shared Actual record query implementation
-------------------------------------------------------------------------------

with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Storage.Journal_Reader; use HRA_N.Storage.Journal_Reader;

package body HRA_N.Application.Actual_Query is

   function Project
     (Journal  : HRA_N.Storage.Journal_Reader.Journal_Result;
      Request  : Query;
      Snapshot : Frontend_Types.Snapshot_Reference :=
        (Kind => Frontend_Types.Snapshot_Unversioned)) return Actual_View
   is
      use HRA_N.Application.Frontend_Types;

      Result : Actual_View :=
        (Status         => Query_Rejected,
         Snapshot       => Snapshot,
         Scope          => Request.Scope,
         Selected_Day   => Request.Selected_Day,
         Ordering       => Request.Ordering,
         Row_Count      => 0,
         Rows           => [others => Empty_Actual_Row],
         Diagnostic     => [others => ' '],
         Diagnostic_Len => 0);

      Missing_Date : Boolean := False;

      procedure Set_Diagnostic (Message : String) is
         Len : constant Natural :=
           Natural'Min (Message'Length, Result.Diagnostic'Length);
      begin
         Result.Diagnostic_Len := Len;
         Result.Diagnostic (1 .. Len) :=
           Message (Message'First .. Message'First + Len - 1);
      end Set_Diagnostic;

      function Comes_Before (Left, Right : Actual_Row) return Boolean is
      begin
         if Left.Has_Date /= Right.Has_Date then
            return Left.Has_Date;
         elsif Left.Has_Date and then not Equal_Date (Left.Valid_On, Right.Valid_On) then
            if Request.Ordering = Order_Oldest_First then
               return Date_Less (Left.Valid_On, Right.Valid_On);
            else
               return Date_Greater (Left.Valid_On, Right.Valid_On);
            end if;
         elsif Request.Ordering = Order_Oldest_First then
            return Left.Source_Order < Right.Source_Order;
         else
            return Left.Source_Order > Right.Source_Order;
         end if;
      end Comes_Before;

   begin
      if not Journal.Success then
         Set_Diagnostic
           ("journal.hra: " &
            Journal.Error_Reason (1 .. Journal.Error_Len));
         return Result;
      end if;

      if Natural (Journal.Events.Length) > Max_Actual_Rows then
         Set_Diagnostic ("journal exceeds bounded Actual query capacity");
         return Result;
      end if;

      for Index in 1 .. Natural (Journal.Events.Length) loop
         declare
            Item        : constant Event := Journal.Events.Element (Positive (Index));
            Item_Id     : constant Event_Id := Id (Item);
            Item_Date   : Date_Type;
            Has_Date    : Boolean;
            Item_Desc   : Description_Text;
            Has_Desc    : Boolean;
            Include_Row : Boolean;
         begin
            Find_Occurrence_Date
              (Journal.Validities, Item_Id, Item_Date, Has_Date);
            Find_Description
              (Journal.Descriptions, Item_Id, Item_Desc, Has_Desc);

            if not Has_Date then
               Missing_Date := True;
            end if;

            Include_Row :=
              Request.Scope = Scope_All
              or else
                (Has_Date and then Equal_Date (Item_Date, Request.Selected_Day));

            if Include_Row then
               Result.Row_Count := Result.Row_Count + 1;
               Result.Rows (Result.Row_Count) :=
                 (Event_Id     => Item_Id.Token,
                  Has_Date     => Has_Date,
                  Valid_On     => Item_Date,
                  Description  =>
                    (if Has_Desc then Item_Desc
                     else (Length => 0, Value => [others => ' '])),
                  Source_Order => Positive (Index));
            end if;
         end;
      end loop;

      if Result.Row_Count > 1 then
         for Index in 2 .. Result.Row_Count loop
            declare
               Key : constant Actual_Row := Result.Rows (Index);
               Pos : Natural := Index - 1;
            begin
               while Pos > 0 and then Comes_Before (Key, Result.Rows (Pos)) loop
                  Result.Rows (Pos + 1) := Result.Rows (Pos);
                  Pos := Pos - 1;
               end loop;
               Result.Rows (Pos + 1) := Key;
            end;
         end loop;
      end if;

      if Missing_Date then
         Result.Status := Query_Partial;
         Set_Diagnostic ("one or more Actual records have no occurrence date");
      else
         Result.Status := Query_Complete;
      end if;

      return Result;
   end Project;

   function Execute
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Request : Query) return Actual_View
   is
      use HRA_N.Application.Frontend_Types;
      use HRA_N.Application.Path_Resolver;

      Snap : Snapshot_Reference := (Kind => Snapshot_Unversioned);
   begin
      if not Paths.Resolution_Ok then
         return
           (Status         => Query_Rejected,
            Snapshot       => (Kind => Snapshot_Unversioned),
            Scope          => Request.Scope,
            Selected_Day   => Request.Selected_Day,
            Ordering       => Request.Ordering,
            Row_Count      => 0,
            Rows           => [others => Empty_Actual_Row],
            Diagnostic     => Paths.Error_Reason,
            Diagnostic_Len => Paths.Error_Len);
      elsif Paths.Is_Versioned then
         Snap :=
           (Kind     => Snapshot_Versioned,
            Identity => Make_Token (Snapshot_Id_Str (Paths)));
      end if;

      declare
         Journal : constant Journal_Result :=
           Read_Journal_File (Journal_Path_Str (Paths));
      begin
         return Project (Journal, Request, Snap);
      end;
   end Execute;

end HRA_N.Application.Actual_Query;
