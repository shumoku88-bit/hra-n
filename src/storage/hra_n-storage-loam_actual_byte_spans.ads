-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Storage.Loam_Actual_Byte_Spans
--
--  Candidate production locator observation for LOAM-NORMALIZED-ACTUAL v1.
--  This package identifies exact byte spans for accepted TX ... ENDTX blocks
--  inside one already-read canonical byte snapshot.  It does not perform
--  semantic admission and does not select a persistent production index.
-------------------------------------------------------------------------------

with HRA_N.Core.Types; use HRA_N.Core.Types;

package HRA_N.Storage.Loam_Actual_Byte_Spans is

   Max_Located_Events : constant := 1_024;

   subtype Located_Event_Count is Natural range 0 .. Max_Located_Events;
   subtype Located_Event_Position is Positive range 1 .. Max_Located_Events;
   subtype Byte_Offset is Natural;

   type Event_Byte_Span is record
      Key        : Event_Id;
      First_Byte : Byte_Offset := 0;
      Last_Byte  : Byte_Offset := 0;
   end record;

   type Event_Byte_Span_Array is
     array (Located_Event_Position) of Event_Byte_Span;

   type Locate_Result is record
      Success : Boolean := False;
      Count   : Located_Event_Count := 0;
      Spans   : Event_Byte_Span_Array;
   end record;

   --  Byte offsets are 1-based relative to Content'First and include the final
   --  LF of ENDTX.  Success only describes structural TX/ENDTX span discovery;
   --  semantic validity still belongs to Loam_Actual_Reader.
   function Locate_Event_Byte_Spans (Content : String) return Locate_Result;

   function Span_Is_Valid
     (Content : String;
      Span    : Event_Byte_Span) return Boolean;

   function Slice_Event_Block
     (Content : String;
      Span    : Event_Byte_Span) return String
   with
     Pre => Span_Is_Valid (Content, Span);

end HRA_N.Storage.Loam_Actual_Byte_Spans;
