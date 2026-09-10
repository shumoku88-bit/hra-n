with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;
with Test_Support;               use Test_Support;

package body Test_Event_Reader is

   procedure Run is
      -- Non-existent file test
      Res_Non_Existent : constant Read_Result :=
        Read_Event_Memory_File ("/non/existent/path.loam");

      -- Real loam data test
      Real_Path : constant String :=
        "/Users/user/Projects/moko/loam-data/movement-authority/objects/Event/100b83b1d62bb00e0f26aa0c08beab00eebffc09a559db75285253638f3c9cb4.loam";

      Res_Real : constant Read_Result := Read_Event_Memory_File (Real_Path);
   begin
      -- Test 1: Non-existent file fails gracefully
      Assert (not Res_Non_Existent.Success, "Non-existent file fails closed");

      -- Test 2: Real loam file loads successfully
      Assert (Res_Real.Success, "Real loam event memory file loads successfully");
      Assert_Equal_Int (588, Long_Long_Integer (Res_Real.Events.Length), "Loaded exact count of 588 events");
   end Run;

end Test_Event_Reader;
