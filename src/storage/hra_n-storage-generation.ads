package HRA_N.Storage.Generation is

   Max_Snapshot_Id_Length : constant := 64;

   type Selection_Result is record
      Success    : Boolean := False;
      Found      : Boolean := False;
      Identity   : String (1 .. Max_Snapshot_Id_Length) := [others => ' '];
      Id_Len     : Natural := 0;
      Error      : String (1 .. 160) := [others => ' '];
      Error_Len  : Natural := 0;
   end record;

   --  Read the sole selector row. Absence is a successful legacy-unversioned
   --  result; malformed or unreadable selectors fail closed.
   function Read_Selection (Base_Dir : String) return Selection_Result;

   function Identity_String (Selection : Selection_Result) return String;

   --  Allocate the next canonical gNNNNNNNN identity.
   function Next_Identity
     (Current : String;
      Next    : out String;
      Length  : out Natural) return Boolean;

end HRA_N.Storage.Generation;
