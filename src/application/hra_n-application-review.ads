-------------------------------------------------------------------------------
--  Shared local-date entrance used by CLI and TUI. The legacy journal review
--  renderer has been retired; do not add presentation or storage access here.
-------------------------------------------------------------------------------

with HRA_N.Core.Validity; use HRA_N.Core.Validity;

package HRA_N.Application.Review is
   function Get_System_Date return Date_Type;
end HRA_N.Application.Review;
