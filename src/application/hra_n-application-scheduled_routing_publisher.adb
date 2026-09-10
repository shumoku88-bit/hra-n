-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Scheduled_Routing_Publisher
-------------------------------------------------------------------------------

with HRA_N.Core.Scheduled_Routing; use HRA_N.Core.Scheduled_Routing;
with HRA_N.Storage.Scheduled_Reader; use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Scheduled_Routing;
with HRA_N.Storage.Atomic_Writer; use HRA_N.Storage.Atomic_Writer;
with HRA_N.Storage.Sync; use HRA_N.Storage.Sync;

package body HRA_N.Application.Scheduled_Routing_Publisher is

   function Set_Error
     (Result : in out Publish_Result; Msg : String) return Publish_Result is
   begin
      Result.Success := False;
      Result.Error_Len := Natural'Min (Msg'Length, Result.Error_Reason'Length);
      Result.Error_Reason (1 .. Result.Error_Len) :=
        Msg (Msg'First .. Msg'First + Result.Error_Len - 1);
      return Result;
   end Set_Error;

   function Publish
     (Routing_Path   : String;
      Scheduled_Path : String;
      Scheduled      : Scheduled_Id;
      Locus          : Locus_Id;
      Effective_On   : Date_Type;
      Target         : Route_Target;
      Purpose        : Token_Text := (Length => 0, Value => [others => ' ']))
      return Publish_Result
   is
      Result : Publish_Result;
      Lock : Lock_Handle;
      Err : String (1 .. 128) := [others => ' '];
      Err_Len : Natural := 0;
   begin
      if Scheduled.Token.Length = 0 or else Locus.Token.Length = 0
        or else (Target = Target_Managed and then Purpose.Length = 0)
        or else (Target = Target_Unmanaged and then Purpose.Length > 0)
      then
         return Set_Error (Result, "Invalid Scheduled routing draft");
      end if;
      if not Acquire_Exclusive_Lock (Routing_Path & ".loam-writer-lock", Lock) then
         return Set_Error (Result, "Failed to acquire Scheduled routing lock");
      end if;
      declare
         Lifecycle_Result : constant Read_Scheduled_Result :=
           Read_Scheduled_File (Scheduled_Path);
         Routing_Result : constant HRA_N.Storage.Scheduled_Routing.Read_Result :=
           HRA_N.Storage.Scheduled_Routing.Read_File (Routing_Path);
      begin
         if not Lifecycle_Result.Success or else not Routing_Result.Success then
            Release_Lock (Lock);
            return Set_Error (Result, "Failed to acquire Scheduled routing authorities");
         end if;
         declare
            Found : constant Lookup_Result :=
              Find_Occurrence (Lifecycle_Result.Lifecycle, Scheduled);
            Contains_Locus : Boolean := False;
            Updated : Routing_History := Routing_Result.History;
         begin
            if not Found.Found then
               Release_Lock (Lock);
               return Set_Error (Result, "Scheduled identity not found");
            end if;
            for I in 1 .. Found.Item.Changes.Count loop
               if Equal_Token (Found.Item.Changes.Values (I).Locus.Token, Locus.Token) then
                  Contains_Locus := True;
               end if;
            end loop;
            if not Contains_Locus or else Updated.Count = Max_Scheduled_Routes then
               Release_Lock (Lock);
               return Set_Error (Result, "Scheduled occurrence does not contain that Locus");
            end if;
            Updated.Count := Updated.Count + 1;
            Updated.Entries (Updated.Count) :=
              (Scheduled => Scheduled, Locus => Locus, Effective_On => Effective_On,
               Managed => Target = Target_Managed, Purpose => Purpose);
            if not Coordinates_Are_Unique (Updated) then
               Release_Lock (Lock);
               return Set_Error (Result, "Scheduled route coordinate/date already exists");
            end if;
            if not Write_File_Atomically
              (Routing_Path, HRA_N.Storage.Scheduled_Routing.Encode (Updated), Err, Err_Len)
            then
               Release_Lock (Lock);
               return Set_Error (Result, "Failed to save Scheduled routing history");
            end if;
            Release_Lock (Lock);
            Result.Success := True;
            return Result;
         end;
      end;
   exception
      when others =>
         Release_Lock (Lock);
         return Set_Error (Result, "Unexpected Scheduled routing publication failure");
   end Publish;

end HRA_N.Application.Scheduled_Routing_Publisher;
