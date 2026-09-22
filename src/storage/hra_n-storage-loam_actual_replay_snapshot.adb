-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Loam_Actual_Replay_Snapshot
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HRA_N.Core.Event;
with HRA_N.Storage.Exact_File;

package body HRA_N.Storage.Loam_Actual_Replay_Snapshot is

   function Empty_Decoded return Event_Block_Result is
     (Decode_Event_Block (""));

   procedure Close_Quietly (Snapshot : in out Replay_Snapshot) is
   begin
      if HRA_N.Storage.Exact_File.Snapshot_Is_Open (Snapshot.Handle) then
         begin
            HRA_N.Storage.Exact_File.Close_Snapshot (Snapshot.Handle);
         exception
            when others =>
               null;
         end;
      end if;
      Snapshot.Count := 0;
   end Close_Quietly;

   procedure Open
     (Snapshot : in out Replay_Snapshot;
      Path     : String;
      Status   : out Snapshot_Open_Status)
   is
      Opened : Boolean;
   begin
      if Is_Open (Snapshot) then
         Status := Snapshot_Already_Open;
         return;
      end if;

      HRA_N.Storage.Exact_File.Open_Snapshot
        (Snapshot.Handle, Path, Opened);

      if not Opened then
         Status := Snapshot_Open_Failed;
         return;
      end if;

      declare
         Exact : constant HRA_N.Storage.Exact_File.Read_Result :=
           HRA_N.Storage.Exact_File.Read_All (Snapshot.Handle);
      begin
         if not Exact.Success then
            Close_Quietly (Snapshot);
            Status := Snapshot_Read_Failed;
            return;
         end if;

         declare
            Bytes   : constant String := To_String (Exact.Content);
            Located : constant Locate_Result :=
              Locate_Event_Byte_Spans (Bytes);
         begin
            if not Located.Success then
               Close_Quietly (Snapshot);
               Status := Snapshot_Locate_Failed;
               return;
            end if;

            if Located.Count > 1 then
               for I in 1 .. Located.Count loop
                  for J in I + 1 .. Located.Count loop
                     if Equal_Token
                       (Located.Spans (I).Key.Token,
                        Located.Spans (J).Key.Token)
                     then
                        Close_Quietly (Snapshot);
                        Status := Snapshot_Duplicate_Event_Id;
                        return;
                     end if;
                  end loop;
               end loop;
            end if;

            Snapshot.Count := Located.Count;
            for I in 1 .. Located.Count loop
               Snapshot.Spans (I) := Located.Spans (I);
            end loop;
         end;
      end;

      Status := Snapshot_Opened;
   exception
      when others =>
         Close_Quietly (Snapshot);
         Status := Snapshot_Open_Failed;
   end Open;

   procedure Close (Snapshot : in out Replay_Snapshot) is
   begin
      Close_Quietly (Snapshot);
   end Close;

   function Is_Open (Snapshot : Replay_Snapshot) return Boolean is
     (HRA_N.Storage.Exact_File.Snapshot_Is_Open (Snapshot.Handle));

   function Event_Count
     (Snapshot : Replay_Snapshot) return Located_Event_Count is
     (if Is_Open (Snapshot) then Snapshot.Count else 0);

   function Replay_Event
     (Snapshot : in out Replay_Snapshot;
      Key      : Event_Id) return Replay_Result
   is
      Empty : constant Event_Block_Result := Empty_Decoded;
   begin
      if not Is_Open (Snapshot) then
         return
           (Status  => Replay_Snapshot_Closed,
            Decoded => Empty);
      end if;

      for I in 1 .. Snapshot.Count loop
         if Equal_Token (Snapshot.Spans (I).Key.Token, Key.Token) then
            declare
               Span : constant Event_Byte_Span := Snapshot.Spans (I);
               Read : constant HRA_N.Storage.Exact_File.Read_Result :=
                 HRA_N.Storage.Exact_File.Read_Range
                   (Snapshot.Handle,
                    Positive (Span.First_Byte),
                    Positive (Span.Last_Byte));
            begin
               if not Read.Success then
                  return
                    (Status  => Replay_Range_Read_Failed,
                     Decoded => Empty);
               end if;

               declare
                  Decoded : constant Event_Block_Result :=
                    Decode_Event_Block (To_String (Read.Content));
               begin
                  if not Decoded.Success then
                     return
                       (Status  => Replay_Decode_Failed,
                        Decoded => Decoded);
                  elsif not Equal_Token
                    (HRA_N.Core.Event.Id (Decoded.Value).Token,
                     Key.Token)
                  then
                     return
                       (Status  => Replay_Identity_Mismatch,
                        Decoded => Decoded);
                  end if;

                  return
                    (Status  => Replay_Succeeded,
                     Decoded => Decoded);
               end;
            end;
         end if;
      end loop;

      return
        (Status  => Replay_Event_Not_Found,
         Decoded => Empty);
   exception
      when others =>
         return
           (Status  => Replay_Range_Read_Failed,
            Decoded => Empty);
   end Replay_Event;

end HRA_N.Storage.Loam_Actual_Replay_Snapshot;
