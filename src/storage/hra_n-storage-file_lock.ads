with GNAT.OS_Lib;

package HRA_N.Storage.File_Lock is

   type Lock_Handle is limited private;
   type Ordered_Lock_Pair is limited private;

   function Acquire
     (Path : String;
      Lock : in out Lock_Handle) return Boolean;

   procedure Release (Lock : in out Lock_Handle);
   function Is_Held (Lock : Lock_Handle) return Boolean;

   --  Acquire two distinct file locks under one in-process exclusion gate.
   --  Cross-process flock acquisition is performed strictly First_Path then
   --  Second_Path.  Release reverses that order and leaves the process gate
   --  only after both file locks have been dropped.
   function Acquire_Ordered_Pair
     (First_Path  : String;
      Second_Path : String;
      Pair        : in out Ordered_Lock_Pair) return Boolean;

   procedure Release (Pair : in out Ordered_Lock_Pair);
   function Is_Held (Pair : Ordered_Lock_Pair) return Boolean;

private
   type Lock_Handle is record
      FD        : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Held      : Boolean := False;
      Gate_Held : Boolean := False;
   end record;

   type Ordered_Lock_Pair is record
      First     : Lock_Handle;
      Second    : Lock_Handle;
      Held      : Boolean := False;
      Gate_Held : Boolean := False;
   end record;
end HRA_N.Storage.File_Lock;
