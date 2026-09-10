-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Scheduled_Publisher
-------------------------------------------------------------------------------

with HRA_N.Core.Types;              use HRA_N.Core.Types;
with HRA_N.Storage.Sync;             use HRA_N.Storage.Sync;
with HRA_N.Storage.Scheduled_Reader; use HRA_N.Storage.Scheduled_Reader;
with HRA_N.Storage.Scheduled_Writer; use HRA_N.Storage.Scheduled_Writer;
with HRA_N.Application.Publisher;    use HRA_N.Application.Publisher;

package body HRA_N.Application.Scheduled_Publisher is

   function Set_Error
     (Result : in out Scheduled_Publish_Result;
      Msg    : String) return Scheduled_Publish_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success      := False;
      Result.Error_Len    := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Complete_Scheduled_Movement
     (Scheduled_Path : String;
      Authority_Dir  : String;
      Target_Id      : Scheduled_Id;
      Valid_On       : Date_Type;
      Description    : String := "") return Scheduled_Publish_Result
   is
      Result : Scheduled_Publish_Result;

      --  1. Preflight inspection of Scheduled lifecycle authority
      Read_Res : constant Read_Scheduled_Result :=
        Read_Scheduled_File (Scheduled_Path);

      Target_Str : constant String :=
        Target_Id.Token.Value (1 .. Target_Id.Token.Length);

      Sched_Lock_Path : constant String := Scheduled_Path & ".loam-writer-lock";
      Sched_Lock      : Lock_Handle;

      Ev_Id_Str : constant String := "scheduled-completion:" & Target_Str;
      Ev_Id     : constant Event_Id := (Token => Make_Token (Ev_Id_Str));
   begin
      if not Read_Res.Success then
         return Set_Error
           (Result, "Failed to read scheduled lifecycle: " &
                    Read_Res.Error_Reason (1 .. Read_Res.Error_Len));
      end if;

      declare
         Lookup : constant Lookup_Result :=
           Find_Occurrence (Read_Res.Lifecycle, Target_Id);
      begin
         if not Lookup.Found then
            return Set_Error (Result, "Scheduled occurrence not found: " & Target_Str);
         end if;

         if not Is_Current_Open (Read_Res.Lifecycle, Target_Id) then
            return Set_Error (Result, "Scheduled occurrence is not current-open: " & Target_Str);
         end if;

         --  Extract balanced 2-party movement shape
         declare
            Occ : constant Scheduled_Occurrence := Lookup.Item;
            From_Locus : String (1 .. Max_Token_Length) := [others => ' '];
            From_Len   : Natural := 0;
            To_Locus   : String (1 .. Max_Token_Length) := [others => ' '];
            To_Len     : Natural := 0;
            Amount     : Quanta_Type := 0;
         begin
            if Occ.Changes.Count /= 2 then
               return Set_Error (Result, "Multi-party scheduled movements not supported in this slice");
            end if;

            for I in 1 .. 2 loop
               declare
                  Chg     : constant Scheduled_Change := Occ.Changes.Values (I);
                  Tok_Str : constant String := Chg.Locus.Token.Value (1 .. Chg.Locus.Token.Length);
               begin
                  if Chg.Amount < 0 then
                     From_Len := Tok_Str'Length;
                     From_Locus (1 .. From_Len) := Tok_Str;
                     Amount := -Chg.Amount;
                  elsif Chg.Amount > 0 then
                     To_Len := Tok_Str'Length;
                     To_Locus (1 .. To_Len) := Tok_Str;
                  end if;
               end;
            end loop;

            if From_Len = 0 or else To_Len = 0 or else Amount <= 0 then
               return Set_Error (Result, "Scheduled changes do not define a balanced FROM/TO pair");
            end if;

            --  2. Acquire Scheduled lifecycle writer ownership
            if not Acquire_Exclusive_Lock (Sched_Lock_Path, Sched_Lock) then
               return Set_Error (Result, "Failed to acquire scheduled lifecycle lock");
            end if;

            --  3. Publish movement under manifest authority with exact scheduled-completion ID
            declare
               Pub_Res : constant Publish_Result :=
                 Publish_Movement
                   (Authority_Dir => Authority_Dir,
                    From_Locus    => From_Locus (1 .. From_Len),
                    To_Locus      => To_Locus (1 .. To_Len),
                    Amount        => Amount,
                    Valid_On      => Valid_On,
                    Description   => Description,
                    Explicit_Id   => Ev_Id_Str);
            begin
               if not Pub_Res.Success then
                  Release_Lock (Sched_Lock);
                  return Set_Error
                    (Result, "Movement publication failed: " &
                             Pub_Res.Error_Reason (1 .. Pub_Res.Error_Len));
               end if;

               --  4. Append Completion to Scheduled lifecycle authority
               declare
                  Write_Res : constant Write_Scheduled_Result :=
                    Append_Completion
                      (Scheduled_Path => Scheduled_Path,
                       Target         => Target_Id,
                       Actual_Event   => Ev_Id);
               begin
                  Release_Lock (Sched_Lock);

                  if not Write_Res.Success then
                     return Set_Error
                       (Result, "Failed to register completion: " &
                                Write_Res.Error_Reason (1 .. Write_Res.Error_Len));
                  end if;

                  Result.Success := True;
                  Result.Event_Id_Len := Ev_Id_Str'Length;
                  Result.Event_Id_Str (1 .. Ev_Id_Str'Length) := Ev_Id_Str;
                  return Result;
               end;
            end;
         end;
      end;
   end Complete_Scheduled_Movement;

end HRA_N.Application.Scheduled_Publisher;
