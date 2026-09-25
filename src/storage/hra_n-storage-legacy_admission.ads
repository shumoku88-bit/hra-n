with HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;
with HRA_N.Storage.Scheduled_Journal_Reader;

--  Transitional three-stream admission law shared by publication and read.
--  This does not establish a Loam-canonical or atomic unversioned snapshot.
package HRA_N.Storage.Legacy_Admission is
   function Failure
     (Journal   : HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy    : HRA_N.Storage.Policy_Reader.Policy_Result;
      Scheduled : HRA_N.Storage.Scheduled_Journal_Reader.Scheduled_Journal_Result)
      return String;
end HRA_N.Storage.Legacy_Admission;
