-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.Application.Review
--
--  Focused record review and projection boundary.
--  Faithfully reproduces Loam's correction-aware occurrence review.
-------------------------------------------------------------------------------

with HRA_N.Core.Validity;           use HRA_N.Core.Validity;
with HRA_N.Core.Description;        use HRA_N.Core.Description;
with HRA_N.Storage.Journal_Reader;   use HRA_N.Storage.Journal_Reader;

package HRA_N.Application.Review is

   type Query_Kind is (Query_Week, Query_Day, Query_Search, Query_Undated);

   Max_Search_Length : constant := 128;

   type Review_Query (Kind : Query_Kind := Query_Week) is record
      case Kind is
         when Query_Week =>
            Ending_Date : Date_Type;
         when Query_Day =>
            Day_Date    : Date_Type;
         when Query_Search =>
            Search_Len  : Natural := 0;
            Search_Text : String (1 .. Max_Search_Length) := [others => ' '];
         when Query_Undated =>
            null;
      end case;
   end record;

   --  Parse user query string ("t", "u", "YYYY-MM-DD", "/text")
   function Parse_Query
     (Query_Str : String;
      Today     : Date_Type;
      Query     : out Review_Query) return Boolean;

   --  Execute review and render output to standard output
   procedure Execute_Review
     (Events       : in Event_Vectors.Vector;
      Validity     : in Validity_Memory;
      Descriptions : in Description_Memory;
      Query        : in Review_Query);

   --  Get today's local date from system calendar clock
   function Get_System_Date return Date_Type;

end HRA_N.Application.Review;
