with HRA_N.Application.Path_Resolver;
with HRA_N.Storage.Journal_Reader;
with HRA_N.Storage.Policy_Reader;

--  Read-only transitional three-stream report entrance. Publishes no result
--  unless the same candidate law as the generation writer admits all streams.
--  An unversioned root has no atomic read snapshot guarantee.
package HRA_N.Application.Legacy_Report_Evidence is
   procedure Read_Admitted
     (Paths   : HRA_N.Application.Path_Resolver.Path_Config;
      Journal : out HRA_N.Storage.Journal_Reader.Journal_Result;
      Policy  : out HRA_N.Storage.Policy_Reader.Policy_Result);
end HRA_N.Application.Legacy_Report_Evidence;
