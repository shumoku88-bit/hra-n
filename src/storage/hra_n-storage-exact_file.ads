with Ada.Strings.Unbounded;

package HRA_N.Storage.Exact_File is
   type Read_Result is record
      Success : Boolean := False;
      Content : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Read_All (Path : String) return Read_Result;

   --  Read one inclusive 1-based byte range from the current file object.
   --  This is a representation experiment for replay locators; callers remain
   --  responsible for binding the range to the intended semantic snapshot.
   function Read_Range
     (Path       : String;
      First_Byte : Positive;
      Last_Byte  : Positive) return Read_Result;
end HRA_N.Storage.Exact_File;
