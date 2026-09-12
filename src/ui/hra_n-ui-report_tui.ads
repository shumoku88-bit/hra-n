-------------------------------------------------------------------------------
--  HRA-N: Verified Household Engine
--  Package: HRA_N.UI.Report_TUI
--
--  Unified financial reports workspace (Financial Statement B/S & P/L,
--  Budget Envelopes, Account Balances) with month navigation and scrolling.
-------------------------------------------------------------------------------

with HRA_N.Application.Path_Resolver;
with HRA_N.Core.Validity;

package HRA_N.UI.Report_TUI is

   type Report_Tab is
     (Tab_Statement,
      Tab_Budget,
      Tab_Balances,
      Tab_Pacing,
      Tab_MoM,
      Tab_Daily_Flow,
      Tab_Audit);

   procedure Run
     (Paths    : HRA_N.Application.Path_Resolver.Path_Config;
      Selected : HRA_N.Core.Validity.Date_Type);

   procedure Export_Cli
     (Paths : HRA_N.Application.Path_Resolver.Path_Config;
      Tab   : Report_Tab;
      Year  : HRA_N.Core.Validity.Year_Type;
      Month : HRA_N.Core.Validity.Month_Type);

end HRA_N.UI.Report_TUI;
