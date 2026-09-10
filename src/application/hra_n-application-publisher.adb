------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Application.Publisher
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;              use Ada.Strings.Fixed;
with HRA_N.Core.Event;               use HRA_N.Core.Event;
with HRA_N.Core.Actual_Routing;      use HRA_N.Core.Actual_Routing;
with HRA_N.Storage.Journal_Reader;   use HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Journal_Writer;   use HRA_N.Storage.Journal_Writer;
with HRA_N.Storage.Policy_Reader;    use HRA_N.Storage.Policy_Reader;

package body HRA_N.Application.Publisher is

   function Set_Error
     (Result : in out Publish_Result;
      Msg    : String) return Publish_Result
   is
      Len : constant Natural := Natural'Min (Msg'Length, Result.Error_Reason'Length);
   begin
      Result.Success := False;
      Result.Error_Len := Len;
      Result.Error_Reason (1 .. Len) := Msg (Msg'First .. Msg'First + Len - 1);
      return Result;
   end Set_Error;

   function Format_Event_Id (Num : Positive) return String is
      Img : constant String := Trim (Num'Image, Ada.Strings.Both);
   begin
      if Img'Length = 1 then
         return "e000" & Img;
      elsif Img'Length = 2 then
         return "e00" & Img;
      elsif Img'Length = 3 then
         return "e0" & Img;
      else
         return "e" & Img;
      end if;
   end Format_Event_Id;

   function Publish_Movement
     (Journal_Path : String;
      Policy_Path  : String;
      From_Locus   : String;
      To_Locus     : String;
      Amount       : Quanta_Type;
      Valid_On     : Date_Type;
      Description  : String := "";
      Explicit_Id  : String := "") return Publish_Result
   is
      Result : Publish_Result;
      JR     : constant Journal_Result := Read_Journal_File (Journal_Path);
      PR     : Policy_Result;
      Purpose_Str : String (1 .. Max_Token_Length) := [others => ' '];
      Purpose_Len : Natural := 0;
      Tx_Id       : String (1 .. 64) := [others => ' '];
      Tx_Len      : Natural := 0;
      Effs        : Effect_List;
      JPY         : constant Measure_Id := (Token => Make_Token ("jpy"));
      Found_Purp  : Token_Text;
      Has_Purp    : Boolean := False;
   begin
      if Amount <= 0 then
         return Set_Error (Result, "Movement amount must be positive");
      end if;

      if From_Locus = To_Locus then
         return Set_Error (Result, "FROM and TO loci must be distinct");
      end if;

      if From_Locus'Length = 0 or else To_Locus'Length = 0 then
         return Set_Error (Result, "Loci cannot be empty");
      end if;

      if not JR.Success then
         return Set_Error (Result, "Failed to read journal: " & JR.Error_Reason (1 .. JR.Error_Len));
      end if;

      --  Determine next EventId
      if Explicit_Id'Length > 0 then
         Tx_Len := Natural'Min (Explicit_Id'Length, Tx_Id'Length);
         Tx_Id (1 .. Tx_Len) := Explicit_Id (Explicit_Id'First .. Explicit_Id'First + Tx_Len - 1);
      else
         declare
            Gen : constant String := Format_Event_Id (Natural (JR.Events.Length) + 1);
         begin
            Tx_Len := Gen'Length;
            Tx_Id (1 .. Tx_Len) := Gen;
         end;
      end if;

      --  Lookup Purpose route in policy if available
      PR := Read_Policy_File (Policy_Path);
      if PR.Success then
         Find_Purpose (PR.Routing, (Token => Make_Token (To_Locus)), Found_Purp, Has_Purp);
         if Has_Purp then
            Purpose_Len := Found_Purp.Length;
            Purpose_Str (1 .. Purpose_Len) := Found_Purp.Value (1 .. Purpose_Len);
         end if;
      end if;

      --  Build effects
      Effs.Count := 2;
      Effs.Values (1) :=
        (Key     => (Token => Make_Token ("0")),
         Locus   => (Token => Make_Token (From_Locus)),
         Measure => JPY,
         Amount  => (Quanta => -Amount));
      Effs.Values (2) :=
        (Key     => (Token => Make_Token ("1")),
         Locus   => (Token => Make_Token (To_Locus)),
         Measure => JPY,
         Amount  => (Quanta => Amount));

      declare
         WR : constant Append_Result := Append_Transaction
           (Journal_Path => Journal_Path,
            Tx_Id        => Tx_Id (1 .. Tx_Len),
            Valid_On     => Valid_On,
            Effects      => Effs,
            Purpose      => Purpose_Str (1 .. Purpose_Len),
            Description  => Description);
      begin
         if not WR.Success then
            return Set_Error (Result, WR.Error_Reason (1 .. WR.Error_Len));
         end if;
      end;

      Result.Success := True;
      Result.Event_Id_Len := Tx_Len;
      Result.Event_Id_Str (1 .. Tx_Len) := Tx_Id (1 .. Tx_Len);
      return Result;
   end Publish_Movement;

   function Publish_Reversal
     (Journal_Path    : String;
      Target_Event_Id : String;
      Valid_On        : Date_Type;
      Description     : String := "") return Publish_Result
   is
      Result    : Publish_Result;
      JR        : constant Journal_Result := Read_Journal_File (Journal_Path);
      Found_Ev  : Event;
      Found     : Boolean := False;
      Tx_Id     : String (1 .. 64) := [others => ' '];
      Tx_Len    : Natural := 0;
      Effs      : Effect_List;
   begin
      if not JR.Success then
         return Set_Error (Result, "Failed to read journal: " & JR.Error_Reason (1 .. JR.Error_Len));
      end if;

      for Ev of JR.Events loop
         declare
            Ev_Id_Tok : constant Event_Id := Id (Ev);
            Ev_Str    : constant String :=
              Ev_Id_Tok.Token.Value (1 .. Ev_Id_Tok.Token.Length);
         begin
            if Ev_Str = Target_Event_Id then
               Found_Ev := Ev;
               Found    := True;
               exit;
            end if;
         end;
      end loop;

      if not Found then
         return Set_Error (Result, "Target event not found in journal: " & Target_Event_Id);
      end if;

      --  Formulate next EventId
      declare
         Gen : constant String := Format_Event_Id (Natural (JR.Events.Length) + 1);
      begin
         Tx_Len := Gen'Length;
         Tx_Id (1 .. Tx_Len) := Gen;
      end;

      --  Invert effects
      Effs := Effects (Found_Ev);
      for I in 1 .. Effs.Count loop
         Effs.Values (I).Amount.Quanta := -Effs.Values (I).Amount.Quanta;
      end loop;

      declare
         Desc_Str : constant String :=
           (if Description'Length > 0 then Description else "Reversal of " & Target_Event_Id);
         WR : constant Append_Result := Append_Transaction
           (Journal_Path => Journal_Path,
            Tx_Id        => Tx_Id (1 .. Tx_Len),
            Valid_On     => Valid_On,
            Effects      => Effs,
            Description  => Desc_Str);
      begin
         if not WR.Success then
            return Set_Error (Result, WR.Error_Reason (1 .. WR.Error_Len));
         end if;
      end;

      Result.Success := True;
      Result.Event_Id_Len := Tx_Len;
      Result.Event_Id_Str (1 .. Tx_Len) := Tx_Id (1 .. Tx_Len);
      return Result;
   end Publish_Reversal;

   function Publish_Correction
     (Journal_Path    : String;
      Policy_Path     : String;
      Target_Event_Id : String;
      From_Locus      : String;
      To_Locus        : String;
      Amount          : Quanta_Type;
      Valid_On        : Date_Type;
      Description     : String := "") return Publish_Result
   is
      Rev_Res : constant Publish_Result := Publish_Reversal
        (Journal_Path    => Journal_Path,
         Target_Event_Id => Target_Event_Id,
         Valid_On        => Valid_On,
         Description     => "Correction: Reversal of " & Target_Event_Id);
   begin
      if not Rev_Res.Success then
         return Rev_Res;
      end if;

      declare
         Desc_Str : constant String :=
           (if Description'Length > 0 then Description else "Correction replacing " & Target_Event_Id);
      begin
         return Publish_Movement
           (Journal_Path => Journal_Path,
            Policy_Path  => Policy_Path,
            From_Locus   => From_Locus,
            To_Locus     => To_Locus,
            Amount       => Amount,
            Valid_On     => Valid_On,
            Description  => Desc_Str);
      end;
   end Publish_Correction;

end HRA_N.Application.Publisher;
