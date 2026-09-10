with Ada.Text_IO; use Ada.Text_IO;
with HRA_N.Core.Types; use HRA_N.Core.Types;
with HRA_N.Core.Event; use HRA_N.Core.Event;
with HRA_N.Core.Correction; use HRA_N.Core.Correction;
with HRA_N.Storage.Event_Reader; use HRA_N.Storage.Event_Reader;
with HRA_N.Storage.Correction;
with HRA_N.Application.Correction_Frontier;
use HRA_N.Application.Correction_Frontier;
with Test_Support; use Test_Support;

package body Test_Correction is
   Path : constant String := "/tmp/hra_n_test_correction.loam";
   procedure Add_Event (Events : in out Event_Vectors.Vector; Name : String) is
      Effects : Effect_List;
   begin
      Effects.Count := 1;
      Effects.Values (1) :=
        (Key => (Token => Make_Token ("k" & Name)),
         Locus => (Token => Make_Token ("cash")),
         Measure => (Token => Make_Token ("jpy")), Amount => (Quanta => 1));
      Events.Append (Make_Event ((Token => Make_Token (Name)), Effects));
   end Add_Event;
   function C (Name, Target, Replacement : String) return Event_Correction is
     ((Id => (Token => Make_Token (Name)), Target => (Token => Make_Token (Target)),
       Replacement => (Token => Make_Token (Replacement))));
   procedure Run is
      Events : Event_Vectors.Vector; Memory : Correction_Memory;
      R : Resolution_Result; F : File_Type;
   begin
      Add_Event (Events, "e1"); Add_Event (Events, "e2"); Add_Event (Events, "e3");
      Memory.Count := 2; Memory.Values (1) := C ("c1", "e1", "e2");
      Memory.Values (2) := C ("c2", "e2", "e3");
      Assert (Frontier_Admissible (Events, Memory), "Linear correction path is admissible");
      Resolve (Events, Memory, (Token => Make_Token ("e1")), R);
      Assert (R.State = Resolution_Current and then R.Depth = 2
              and then Equal_Token (R.Effective.Token, Make_Token ("e3")),
              "Correction chain resolves to terminal replacement");
      Resolve (Events, Memory, (Token => Make_Token ("absent")), R);
      Assert (R.State = Resolution_Absent, "Missing original remains absent");

      Memory.Values (2) := C ("c2", "e1", "e3");
      Assert (not Frontier_Admissible (Events, Memory),
              "Sibling correction branches remain unresolved");
      Memory.Values (2) := C ("c2", "e3", "e2");
      Assert (not Frontier_Admissible (Events, Memory),
              "Two correction parents cannot merge silently");
      Memory.Values (2) := C ("c2", "e2", "e1");
      Assert (not Frontier_Admissible (Events, Memory), "Correction cycle is rejected");
      Memory.Values (2) := C ("c2", "e2", "missing");
      Assert (not Frontier_Admissible (Events, Memory),
              "Missing correction endpoint fails closed");

      Memory.Count := 1; Memory.Values (1) := C ("c1", "e1", "e2");
      Create (F, Out_File, Path); Put (F, HRA_N.Storage.Correction.Encode (Memory)); Close (F);
      declare Read : constant HRA_N.Storage.Correction.Read_Result :=
        HRA_N.Storage.Correction.Read_File (Path);
      begin
         Assert (Read.Success and then Read.Memory.Count = 1,
                 "Correction v1 encoding round-trips");
         Assert (Ids_Are_Unique (Read.Memory), "Correction persistence retains unique ids");
      end;

      Create (F, Out_File, Path);
      Put_Line (F, "LOAM-EVENT-CORRECTION-MEMORY" & ASCII.HT & "1");
      Put_Line (F, "CORRECTION" & ASCII.HT & "c1" & ASCII.HT & "e1" & ASCII.HT & "e2");
      Put_Line (F, "CORRECTION" & ASCII.HT & "c1" & ASCII.HT & "e2" & ASCII.HT & "e3");
      Close (F);
      declare Read : constant HRA_N.Storage.Correction.Read_Result :=
        HRA_N.Storage.Correction.Read_File (Path);
      begin
         Assert (not Read.Success, "Duplicate correction identity is rejected by memory boundary");
      end;
   end Run;
end Test_Correction;
