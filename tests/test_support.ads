-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: Test_Support
--
--  Lightweight assertion and reporting harness for unit test suites.
-------------------------------------------------------------------------------

package Test_Support is

   procedure Assert
     (Condition : Boolean;
      Message   : String);

   procedure Assert_Equal_Int
     (Expected : Long_Long_Integer;
      Actual   : Long_Long_Integer;
      Message  : String);

   procedure Assert_Equal_Bool
     (Expected : Boolean;
      Actual   : Boolean;
      Message  : String);

   --  Extend the freshly initialized g00000001 policy before any proposal.
   --  This is fixture construction, not a production write path.
   procedure Append_Initial_Policy
     (Base_Dir : String;
      Content  : String);

   procedure Report_Summary (Suite_Name : String);

   function All_Passed return Boolean;

   function Real_Data_Available return Boolean;
   function Real_Data_Dir return String;

end Test_Support;
