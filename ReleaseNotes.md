# Release Notes
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
  - Editing Policy Names
  - Editing Policy Description
  - Implementing Connect-ToMgGraph -> Created By thiago beierhttps://github.com/thiagogbeier/Connect-To-MgGraph
    - Implemented Intune Toolkit Logging
    - Optimizing Ms Graph Module Detection & Installation
    - Implemented Interactive Logon
    - Implemented App Registration Logon
- **BugFix**
  - Fixed issue with assignments of Microsoft Store app (new) => Issue #25
- **Other**
  - Added A CODE OF CONDUCT
  - Added CONTRIBUTION GUIDELINES
  - Split up Release notes from ReadMe File

### v0.2.5-alpha
- **Performance Upgrades**
  - Enhanced performance of security group fetching by adding additional filters to Graph API calls, reducing load times.
  - Introduced a manual sync button for on-demand updates of security groups.
  - Removed automatic security group fetching when loading policies/applications to prevent delays in large tenants.
    - Security groups are now loaded at startup or through manual refresh. 

### v0.2.4-alpha
- **BugFix**
  - moved powershell validation to before check microsoft.graph module ->  contribution By thiagogbeier

### v0.2.3-alpha
- **Features**
  - added log file to $env: as %temp% location under current user context/scope -> contribution By thiagogbeier
  - added the powershell 7.0.0 as minimum requirement as per in documentation validation with end-user notification to upgrade or open powershell 7.x -> contribution By thiagogbeier
 
### v0.2.2-alpha
- **Features**
  - Assignments
    - Managed Google Play Store App
    - IOS Store App
  - Platform Inormation
  - Update to "Export to Mark Down (MD)"
    - Table of Contents
    - Platfrom Information  
 
### v0.2.1-alpha
- **Bug Fixes**
  - Assignment Issue with Device confiuration poilicy (Settings Catalog)

### v0.2.0-alpha
- **Features**
  - Mac OS Scripts
  - App Configuration Policies
  - Document To markdown
    - Selected Policies / applications
    - Bulk Export of Policy Type
  - Basic Version Check to latest Release Version on Github
- **Bug Fixes**
  - Build in safety when no filters Exists ( Second Attempt ;-) )

### v0.1.1-alpha
- **Features**
  - Platform scripts
  - Export To CSV
- **UI**
  - Updated UI
  - Remove install intent column in policy Context
- **Bug Fixes**
  -Build in safety when no filters Exists
  -Checks for MS Graph Module
