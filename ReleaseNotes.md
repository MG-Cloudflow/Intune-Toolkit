# Release Notes
### v0.3.2.0
- **New Features**
  - **Export Comparison Report**
    - When comparing against a baseline, you can now export the report as CSV or Markdown.
  - **New Application Types for Assignments**
    - androidForWorkApp
    - androidLobApp
    - androidStoreApp
    - iosLobApp
    - iosVppApp

- **Bug Fixes & UI Improvements**
  - **Assignment Creation**
    - Fixed an issue when no security groups are present in the tenant.

### v0.3.1.0
- **New Features**
  - **Confirmation Pop-Ups**
    - When Adding assignments there is now a confirmation pop up with an overview
    - For Adding or Deteleting Assignments there is now a Copy To clibpoard Feature in the overview giving you the option to document the changes in your documentaion.
  - **3th Party Baseline Comparisons**
    - You can now compare your Intune Configuration Policies (Settings Catalog) to 3th party baselines or your own created baseline
    - Big Thank you for @oktay-sari for providing me with the AllThingsCloud - MacOS Security Baselines [https://github.com/oktay-sari/]
    - Also a Big Thank you to @SkipToTheEndpoint for providing me the OpenIntune Baseline [https://github.com/SkipToTheEndpoint]
  - **MacOS Baseline Comparisons**
    - Added Functionality to compare macOS Settings catalog templates
- **Bug Fixes & UI Improvements**
  - **Baseline Comparisons**
    - Fixed Comparison issues on deeper levels in the json file
  - **UI**
    - Added Visual Intune Toolkit Version to the ui

### v0.3.0.0
- **New Features**
  - **Custom Attributes Management for macOS**
    - Added support for **bulk assignment** of macOS custom attributes, streamlining device management at scale.
    - Introduced functionality for **bulk deletion** of macOS custom attributes, improving efficiency in policy cleanup.
    - **Document Assignments** feature enables comprehensive tracking and reporting of macOS custom attribute configurations.
      - added extra platfrom information to markdown file
    - **Backup and Restore** capabilities now support macOS custom attribute assignments, ensuring quick recovery and replication of configurations.
- **Bug Fixes & UI Improvements**
  - Resolved an issue where **disabled buttons** appeared incorrectly enabled in certain UI states.
  - Adjusted button text in the **Security Baseline Analysis Report** feature to prevent truncation and improve readability.
  - Removed Filter Collums from UI where Filters Cannot be Assigned to
  - Disabled Filter Fields when assigning to Polcies that dont support filters
  - Build In safty to check if both filter fields are filled in before you can assign the policy if one of them is assinged
  - Fixed issue #36
  - Add Intune-Toolki Icon
  - Cleanup Code & Added extra Comments in the Code to make it more readable
  - Correct naming of macOS Platform ;-)

### v0.2.9.0
- **New Features**
  - **Security Baseline Analysis Report**
    - Added a new feature to merge settings from selected configuration policies and compare them against the Windows 24H2 baseline.
    - Generates a comprehensive Markdown report that includes:
      - A summary of total baseline settings, number of settings that match, differ, and are missing.
      - A detailed "Baseline Settings Comparison" table showing the description, expected values, configured policies, actual values, and comparison results.
      - An "Extra Settings" table listing settings present in the merged configuration but not defined in the baseline.
    - Integrated a Save File dialog allowing users to choose where to export the Markdown report.
    - Implements caching of the settings catalog locally to improve performance on subsequent runs.
  
### v0.2.8.0
- **New Features**
  - **Device Management Intents**
    - Added comprehensive support for Device Management Intents, enabling you to view and manage intents with detailed assignment data.
    - Introduced a dedicated `IntentsButton` to easily load and refresh intent policies.
    - Updated the assignment retrieval logic to perform individual API calls per intent policy, ensuring that even if the assignments are not returned in bulk, they are still fetched accurately.
    - Enhanced error handling and logging for intent processing, providing clearer diagnostics if an intent fails to load or update.
  - **Delete Safety**
    - Implemented a robust confirmation popup for deletion operations. Before any assignment deletion, users now see a detailed overview of the assignments that are about to be removed.
    - The confirmation dialog displays a summary (including policy IDs and group names) and requires explicit user consent by clicking OK.
    - This additional safety measure prevents accidental deletion of assignments and improves overall user confidence in the toolkit.
  - **Assignments to ALL Users and ALL Devices**
    - Resolved previous issues with assignments targeting “All Users” and “All Devices”. These special assignment types now work as intended, with proper handling in both the UI and the underlying API calls.
- **Bug Fixes**
  - Fixed issues in assignment processing for intents when no assignments were returned directly.
  - Addressed bugs causing errors when applying new assignments if the same policy was selected multiple times (see earlier versions for more details).

### v0.2.7.1-alpha
- **BugFix**
  - Fixed an issue where errors would occur when applying new assignments if the same policy was selected multiple times.

### v0.2.7-alpha
- **Code Optimization**
  - **Assignments**
    - Refactored assignment logic by splitting the assignment button handling into a separate function file for better maintainability and clarity.
    - Prepared the structure to support new application types in future releases.
  - **Graph Module**
    - Optimized module installations to include only the essential Graph module: `Microsoft.Graph.Authentication`.
    - Added a confirmation popup that prompts users before installing any required modules, improving user control over the installation process.

### v0.2.6-alpha
- **Features**
  - Editing Policy Names.
  - Editing Policy Description.
  - Implementing Connect-ToMgGraph → Created by [thiago beier](https://github.com/thiagogbeier/Connect-To-MgGraph)
    - Implemented Intune Toolkit Logging.
    - Optimized MS Graph Module Detection & Installation.
    - Implemented Interactive Logon.
    - Implemented App Registration Logon.
- **BugFix**
  - Fixed issue with assignments of Microsoft Store app (new) → Issue #25.
- **Other**
  - Added a CODE OF CONDUCT.
  - Added CONTRIBUTION GUIDELINES.
  - Split up Release notes from the ReadMe File.

### v0.2.5-alpha
- **Performance Upgrades**
  - Enhanced performance of security group fetching by adding additional filters to Graph API calls, reducing load times.
  - Introduced a manual sync button for on-demand updates of security groups.
  - Removed automatic security group fetching when loading policies/applications to prevent delays in large tenants.
    - Security groups are now loaded at startup or through manual refresh.

### v0.2.4-alpha
- **BugFix**
  - Moved PowerShell validation to before checking the Microsoft.Graph module. *(Contribution by thiagogbeier)*

### v0.2.3-alpha
- **Features**
  - Added log file to `$env:` as `%temp%` location under the current user context/scope. *(Contribution by thiagogbeier)*
  - Set PowerShell 7.0.0 as the minimum requirement with end-user notification to upgrade or open PowerShell 7.x. *(Contribution by thiagogbeier)*

### v0.2.2-alpha
- **Features**
  - Assignments:
    - Managed Google Play Store App.
    - iOS Store App.
  - Platform Information.
  - Updated "Export to Markdown (MD)":
    - Table of Contents.
    - Platform Information.

### v0.2.1-alpha
- **Bug Fixes**
  - Fixed assignment issue with Device Configuration Policy (Settings Catalog).

### v0.2.0-alpha
- **Features**
  - Mac OS Scripts.
  - App Configuration Policies.
  - Document to Markdown:
    - Selected Policies / Applications.
    - Bulk Export of Policy Type.
  - Basic Version Check against the latest release on GitHub.
- **Bug Fixes**
  - Built-in safety when no filters exist (Second Attempt ;-) ).

### v0.1.1-alpha
- **Features**
  - Platform Scripts.
  - Export to CSV.
- **UI**
  - Updated UI.
  - Removed install intent column in policy context.
- **Bug Fixes**
  - Built-in safety when no filters exist.
  - Checks for MS Graph Module.
