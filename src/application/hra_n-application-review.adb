with Ada.Calendar;

package body HRA_N.Application.Review is
   function Get_System_Date return Date_Type is
      Now  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Y    : Ada.Calendar.Year_Number;
      M    : Ada.Calendar.Month_Number;
      D    : Ada.Calendar.Day_Number;
      Secs : Ada.Calendar.Day_Duration;
   begin
      Ada.Calendar.Split (Now, Y, M, D, Secs);
      return Make_Date (Y, M, D);
   end Get_System_Date;
end HRA_N.Application.Review;
