-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Journal_Writer
--
--  Atomic append operations for canonical journal.hra files.
-------------------------------------------------------------------------------

with HRA_N.Core.Types;    use HRA_N.Core.Types;
with HRA_N.Core.Validity; use HRA_N.Core.Validity;
with HRA_N.Core.Event;    use HRA_N.Core.Event;
with HRA_N.Core.Relation; use HRA_N.Core.Relation;

package HRA_N.Storage.Journal_Writer is

   type Append_Result is record
      Success      : Boolean := False;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Encode_Transaction
     (Tx_Id         : String;
      Valid_On      : Date_Type;
      Effects       : Effect_List;
      Purpose       : String := "";
      Description   : String := "";
      Replaces_Id   : String := "";
      Relation_Str  : String := "";
      Discharge_Str : String := "";
      Reverses_Id   : String := "") return String;

   function Append_Transaction
     (Journal_Path : String;
      Tx_Id        : String;
      Valid_On     : Date_Type;
      Effects      : Effect_List;
      Purpose       : String := "";
      Description   : String := "";
      Replaces_Id   : String := "";
      Relation_Str  : String := "";
      Discharge_Str : String := "";
      Reverses_Id   : String := "") return Append_Result;

   function Encode_Assertion
     (As_Id       : String;
      Valid_On    : Date_Type;
      Locus       : String;
      Measure     : String;
      Amount      : Quanta_Type;
      Description : String := "") return String;

   --  Canonical relation encodings. Endpoint rendering (household versus
   --  ext:<name>) lives here so every writer emits one byte shape.
   function Encode_Endpoint (Endpoint : Relation_Endpoint) return String;

   function Encode_Relation
     (Claim_Id   : String;
      Source_Tx  : String;
      Debtor     : String;
      Creditor   : String;
      Measure    : String;
      Amount     : Quanta_Type) return String;

   function Encode_Discharge
     (Settlement_Tx : String;
      Claim_Id      : String;
      Amount        : Quanta_Type) return String;

end HRA_N.Storage.Journal_Writer;
