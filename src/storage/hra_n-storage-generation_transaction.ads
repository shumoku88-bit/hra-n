package HRA_N.Storage.Generation_Transaction is

   type Fault_Point is
     (No_Fault,
      After_Lock,
      After_Candidate_Directory,
      After_Journal_Write,
      After_Policy_Write,
      After_Scheduled_Write,
      After_Admission,
      After_Activation);

   type Commit_Result is record
      Success      : Boolean := False;
      Snapshot_Id  : String (1 .. 64) := [others => ' '];
      Snapshot_Len : Natural := 0;
      Error         : String (1 .. 160) := [others => ' '];
      Error_Len     : Natural := 0;
   end record;

   --  Commit a complete three-stream candidate against Expected_Snapshot.
   --  The candidate is parsed and admitted before CURRENT activation.
   function Commit
     (Base_Dir           : String;
      Expected_Snapshot  : String;
      Journal_Content    : String;
      Policy_Content     : String;
      Scheduled_Content  : String;
      Inject_Fault       : Fault_Point := No_Fault) return Commit_Result;

end HRA_N.Storage.Generation_Transaction;
