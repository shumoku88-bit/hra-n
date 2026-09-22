-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Event_Block
--
--  Local decoder for exactly one LOAM-NORMALIZED-ACTUAL v1 TX ... ENDTX block.
--  It validates the Event and evidence encoded inside that block, but it does
--  not perform document-global admission such as replacement/reversal closure
--  or comparison with another Event.
-------------------------------------------------------------------------------

with HRA_N.Core.Description;          use HRA_N.Core.Description;
with HRA_N.Core.Event;                use HRA_N.Core.Event;
with HRA_N.Core.Transaction_Metadata; use HRA_N.Core.Transaction_Metadata;
with HRA_N.Core.Validity;             use HRA_N.Core.Validity;

package HRA_N.Storage.Loam_Actual_Event_Block is

   type Event_Block_Result is record
      Success         : Boolean;
      Value           : Event;
      Validity        : Validity_Entry;
      Has_Description : Boolean;
      Description     : Description_Entry;
      Metadata        : Transaction_Metadata_Entry;
      Error_Line      : Natural;
      Error_Reason    : String (1 .. 160);
      Error_Len       : Natural;
   end record;

   --  Block begins with TX and ends with ENDTX + LF. REPLACES and REVERSAL-OF
   --  are retained as local metadata even when their target Events are absent
   --  from Block. Referential/global validity belongs to document admission.
   function Decode_Event_Block (Block : String) return Event_Block_Result;

end HRA_N.Storage.Loam_Actual_Event_Block;
