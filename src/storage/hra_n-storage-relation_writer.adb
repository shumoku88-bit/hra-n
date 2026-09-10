-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: HRA_N.Storage.Relation_Writer
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with HRA_N.Core.Types; use HRA_N.Core.Types;

package body HRA_N.Storage.Relation_Writer is

   function Token_Image (Value : Token_Text) return String is
     (Value.Value (1 .. Value.Length));

   function Quanta_Image (Value : Quanta_Type) return String is
     (Trim (Value'Image, Ada.Strings.Both));

   procedure Append_Endpoint
     (Text     : in out Unbounded_String;
      Endpoint : Relation_Endpoint)
   is
   begin
      case Endpoint.Kind is
         when Endpoint_Household =>
            Append (Text, "H" & ASCII.HT);
         when Endpoint_External =>
            Append (Text, "E" & ASCII.HT & Token_Image (Endpoint.External_Id));
      end case;
   end Append_Endpoint;

   function Encode_Relation_Units (Memory : Unit_Memory) return String is
      Text : Unbounded_String := To_Unbounded_String
        ("LOAM-RELATION-UNIT-MEMORY" & ASCII.HT & "1" & ASCII.LF);
   begin
      for I in 1 .. Memory.Count loop
         declare
            Value : constant Relation_Unit := Memory.Units (I);
         begin
            Append
              (Text,
               "RELATION" & ASCII.HT & Token_Image (Value.Id) & ASCII.HT &
               Token_Image (Value.Source_Event.Token) & ASCII.HT &
               Token_Image (Value.Source_Effect.Token) & ASCII.HT);
            Append_Endpoint (Text, Value.Debtor);
            Append (Text, ASCII.HT);
            Append_Endpoint (Text, Value.Creditor);
            Append (Text, ASCII.HT & Quanta_Image (Value.Quantity) & ASCII.LF);
         end;
      end loop;
      return To_String (Text);
   end Encode_Relation_Units;

   function Encode_Relation_Discharges
     (Memory : Discharge_Memory) return String
   is
      Text : Unbounded_String := To_Unbounded_String
        ("LOAM-RELATION-DISCHARGE-MEMORY" & ASCII.HT & "1" & ASCII.LF);
   begin
      for I in 1 .. Memory.Count loop
         declare
            Value : constant Relation_Discharge := Memory.Discharges (I);
         begin
            Append
              (Text,
               "DISCHARGE" & ASCII.HT & Token_Image (Value.Event.Token) &
               ASCII.HT & Token_Image (Value.Target) & ASCII.HT &
               Quanta_Image (Value.Quantity) & ASCII.LF);
         end;
      end loop;
      return To_String (Text);
   end Encode_Relation_Discharges;

end HRA_N.Storage.Relation_Writer;
