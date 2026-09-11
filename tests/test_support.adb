-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package body: Test_Support
-------------------------------------------------------------------------------

with Ada.Text_IO;               use Ada.Text_IO;
with Ada.Directories;
with Ada.Environment_Variables;

package body Test_Support is

   Total_Count  : Natural := 0;
   Passed_Count : Natural := 0;
   Failed_Count : Natural := 0;

   procedure Assert
     (Condition : Boolean;
      Message   : String)
   is
   begin
      Total_Count := Total_Count + 1;
      if Condition then
         Passed_Count := Passed_Count + 1;
         Put_Line ("    [PASS] " & Message);
      else
         Failed_Count := Failed_Count + 1;
         Put_Line ("    [FAIL] " & Message);
      end if;
   end Assert;

   procedure Assert_Equal_Int
     (Expected : Long_Long_Integer;
      Actual   : Long_Long_Integer;
      Message  : String)
   is
   begin
      if Expected = Actual then
         Assert (True, Message);
      else
         Assert
           (False,
            Message & " (expected: " & Long_Long_Integer'Image (Expected) &
            ", got: " & Long_Long_Integer'Image (Actual) & ")");
      end if;
   end Assert_Equal_Int;

   procedure Assert_Equal_Bool
     (Expected : Boolean;
      Actual   : Boolean;
      Message  : String)
   is
   begin
      if Expected = Actual then
         Assert (True, Message);
      else
         Assert
           (False,
            Message & " (expected: " & Boolean'Image (Expected) &
            ", got: " & Boolean'Image (Actual) & ")");
      end if;
   end Assert_Equal_Bool;

   procedure Append_Initial_Policy
     (Base_Dir : String;
      Content  : String)
   is
      File : Ada.Text_IO.File_Type;
      Path : constant String :=
        Base_Dir & "/.hra/generations/g00000001/policy.hra";
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.Append_File, Path);
      Ada.Text_IO.Put (File, Content);
      Ada.Text_IO.Close (File);
   end Append_Initial_Policy;

   procedure Report_Summary (Suite_Name : String) is
   begin
      Put_Line ("--- Suite: " & Suite_Name & " ---");
      Put_Line ("Total: " & Natural'Image (Total_Count) &
                ", Passed: " & Natural'Image (Passed_Count) &
                ", Failed: " & Natural'Image (Failed_Count));
   end Report_Summary;

   function All_Passed return Boolean is
   begin
      return Failed_Count = 0;
   end All_Passed;

   function Real_Data_Dir return String is
   begin
      if Ada.Environment_Variables.Exists ("LOAM_DATA_DIR") then
         return Ada.Environment_Variables.Value ("LOAM_DATA_DIR");
      elsif Ada.Directories.Exists ("/Users/user/Projects/moko/loam-data") then
         return "/Users/user/Projects/moko/loam-data";
      else
         return "";
      end if;
   end Real_Data_Dir;

   function Real_Data_Available return Boolean is
      D : constant String := Real_Data_Dir;
   begin
      return D'Length > 0 and then Ada.Directories.Exists (D & "/movement-authority/CURRENT");
   end Real_Data_Available;

end Test_Support;
