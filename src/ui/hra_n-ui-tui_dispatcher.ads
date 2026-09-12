-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.TUI_Dispatcher
--
--  Central entry point for launching interactive Curses-based TUI workspaces,
--  handling Curses lifecycle initialization and teardown safely.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver; use HRA_N.Application.Path_Resolver;

package HRA_N.UI.TUI_Dispatcher is

   --  Launch an interactive TUI workspace by name.
   --  Supported workspaces:
   --    home, record, actual, scheduled, capacity, budget, attention,
   --    balance, report, route, locus
   procedure Dispatch
     (Paths     : Path_Config;
      Workspace : String;
      Success   : out Boolean);

   --  Convenience: directly launch Record_TUI form
   procedure Run_Record
     (Paths     : Path_Config;
      Committed : out Boolean);

   --  Print list of available workspaces to stdout
   procedure Print_Workspaces;

end HRA_N.UI.TUI_Dispatcher;
