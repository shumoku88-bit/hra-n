with GNAT.OS_Lib;

package HRA_N.Storage.File_Lock is

   type Lock_Handle is limited private;

   function Acquire
     (Path : String;
      Lock : in out Lock_Handle) return Boolean;

   procedure Release (Lock : in out Lock_Handle);
   function Is_Held (Lock : Lock_Handle) return Boolean;

private
   type Lock_Handle is record
      FD   : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Held      : Boolean := False;
      Gate_Held : Boolean := False;
   end record;
end HRA_N.Storage.File_Lock;
