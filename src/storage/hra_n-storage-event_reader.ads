with Ada.Containers.Vectors;
with HRA_N.Core.Event; use HRA_N.Core.Event;

package HRA_N.Storage.Event_Reader is

   package Event_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Event);

   type Read_Result is record
      Success      : Boolean := False;
      Events       : Event_Vectors.Vector;
      Error_Line   : Natural := 0;
      Error_Reason : String (1 .. 128) := [others => ' '];
      Error_Len    : Natural := 0;
   end record;

   function Read_Event_Memory_File (Path : String) return Read_Result;

end HRA_N.Storage.Event_Reader;
