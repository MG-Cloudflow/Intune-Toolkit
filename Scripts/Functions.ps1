<#
.SYNOPSIS
Functions for managing Microsoft Intune policies and data retrieval via Microsoft Graph API.

.DESCRIPTION
This script contains functions to manage and retrieve data related to Microsoft Intune policies. 
Functions include retrieving security groups, assignment filters, paginated data from the Graph API, 
reloading grid data, and loading policy data. Error handling and logging are implemented in each function.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 12/02/2025

.EXAMPLE
$groups = Get-AllSecurityGroups
$filters = Get-AllAssignmentFilters
$data = Get-GraphData -url "https://graph.microsoft.com/beta/deviceManagement/..."
Reload-Grid -type "deviceConfigurations"
Load-PolicyData -policyType "deviceConfigurations" -loadingMessage "Loading..." -loadedMessage "Loaded."
#>

#--------------------------------------------------------------------------------
# Function: Get-AllSecurityGroups
# Retrieves all security-enabled groups from Microsoft Graph.
#--------------------------------------------------------------------------------
function Get-AllSecurityGroups {
    Write-IntuneToolkitLog "Starting Get-AllSecurityGroups" -component "Get-AllSecurityGroups" -file "Functions.ps1"
    try {
        $url = "https://graph.microsoft.com/beta/groups?`$filter=securityEnabled eq true&`$select=id,displayName"
        Write-IntuneToolkitLog "Fetching all security groups with pagination from $url" -component "Get-AllSecurityGroups" -file "Functions.ps1"
        $allGroups = Get-GraphData -url $url
        Write-IntuneToolkitLog "Successfully fetched all security groups" -component "Get-AllSecurityGroups" -file "Functions.ps1"
        return $allGroups
    } catch {
        $errorMessage = "Failed to get all security groups: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Get-AllSecurityGroups" -file "Functions.ps1"
    }
}

#--------------------------------------------------------------------------------
# Function: Set-WindowIcon
# The WPF window object whose icon will be set.
# Set-WindowIcon -Window $Window -IconFile "MyOtherIcon.ico"
# Set-WindowIcon -Window $Window
#--------------------------------------------------------------------------------
function Set-WindowIcon {
    param (
        # The WPF window object whose icon will be set.
        [Parameter(Mandatory = $true)]
        [System.Windows.Window]$Window,

        # Optional: The icon file name (default is "Intune-toolkit.ico").
        [Parameter(Mandatory = $false)]
        [string]$IconFile = "Intune-toolkit.ico"
    )

    try {
        # Build the full path to the icon file.
        $iconPath = ".\$($IconFile)"

        if (Test-Path $iconPath) {
            # Resolve the full path and convert backslashes to forward slashes.
            $resolvedIconPath = (Resolve-Path $iconPath).Path
            $formattedPath = $resolvedIconPath -replace '\\', '/'

            # Build a proper file URI.
            $uriString = "file:///" + $formattedPath
            $uri = New-Object System.Uri($uriString)

            # Create a BitmapFrame from the URI and assign it to the window's Icon.
            $iconBitmap = [System.Windows.Media.Imaging.BitmapFrame]::Create($uri)
            $Window.Icon = $iconBitmap

            Write-IntuneToolkitLog "Icon set successfully from $iconPath" -component "Set-WindowIcon" -file "Common.ps1"
        }
        else {
            Write-IntuneToolkitLog "Icon file not found at $iconPath" -component "Set-WindowIcon" -file "Common.ps1"
        }
    }
    catch {
        Write-IntuneToolkitLog "Failed to set icon: $($_.Exception.Message)" -component "Set-WindowIcon" -file "Common.ps1"
    }
}

#--------------------------------------------------------------------------------
# Function: Get-AllAssignmentFilters
# Retrieves all assignment filters from Microsoft Graph and formats them.
#--------------------------------------------------------------------------------
function Get-AllAssignmentFilters {
    Write-IntuneToolkitLog "Starting Get-AllAssignmentFilters" -component "Get-AllAssignmentFilters" -file "Functions.ps1"
    try {
        $url = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
        Write-IntuneToolkitLog "Fetching all assignment filters with pagination from $url" -component "Get-AllAssignmentFilters" -file "Functions.ps1"
        $allFilters = Get-GraphData -url $url
        $formattedFilters = $allFilters | ForEach-Object {
            [PSCustomObject]@{
                Id          = $_.id
                DisplayName = $_.displayName
            }
        }
        Write-IntuneToolkitLog "Successfully fetched all assignment filters" -component "Get-AllAssignmentFilters" -file "Functions.ps1"
        return $formattedFilters
    } catch {
        $errorMessage = "Failed to get all assignment filters: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Get-AllAssignmentFilters" -file "Functions.ps1"
    }
}

#--------------------------------------------------------------------------------
# Function: Get-GraphData
# Retrieves data from Microsoft Graph API with support for pagination.
#--------------------------------------------------------------------------------
function Get-GraphData {
    param (
        [Parameter(Mandatory=$true)]
        [string] $url
    )
    Write-IntuneToolkitLog "Starting Get-GraphData for $url" -component "Get-GraphData" -file "Functions.ps1"
    try {
        $results = @()
        do {
            Write-IntuneToolkitLog "Fetching data from $url" -component "Get-GraphData" -file "Functions.ps1"
            $response = Invoke-MgGraphRequest -Uri $url -Method GET
            if ($response.'@odata.nextLink' -ne $null) {
                $url = $response.'@odata.nextLink'
                Write-IntuneToolkitLog "Next page URL: $url" -component "Get-GraphData" -file "Functions.ps1"
                $results += $response.value
            } else {
                $results += $response.Value
                Write-IntuneToolkitLog "Successfully fetched all data" -component "Get-GraphData" -file "Functions.ps1"
                return $results
            }
        } while ($response.'@odata.nextLink')
    } catch {
        $errorMessage = "Failed to get data from Graph API: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Get-GraphData" -file "Functions.ps1"
    }
}

#--------------------------------------------------------------------------------
# Function: Get-PlatformApps
# Determines the platform (Android, iOS, Windows, macOS, Web) for an app based on its OData type.
#--------------------------------------------------------------------------------
function Get-PlatformApps {
    param (
        [Parameter(Mandatory = $false)]
        [string]$odataType
    )

    switch ($odataType) {
        "#microsoft.graph.androidStoreApp"        { $platform = "Android" }
        "#microsoft.graph.androidLobApp"          { $platform = "Android" }
        "#microsoft.graph.androidManagedStoreApp" { $platform = "Android" }
        "#microsoft.graph.androidForWorkApp"      { $platform = "Android" }
        
        "#microsoft.graph.iosStoreApp"            { $platform = "iOS" }
        "#microsoft.graph.iosLobApp"              { $platform = "iOS" }
        "#microsoft.graph.iosVppApp"              { $platform = "iOS" }
        "#microsoft.graph.iosWebClip"             { $platform = "iOS" }
        
        "#microsoft.graph.win32LobApp"            { $platform = "Windows" }
        "#microsoft.graph.windowsUniversalAppX"   { $platform = "Windows" }
        "#microsoft.graph.windowsStoreApp"        { $platform = "Windows" }
        "#microsoft.graph.windowsMicrosoftEdgeApp"{ $platform = "Windows" }
        "#microsoft.graph.microsoftStoreForBusinessApp" { $platform = "Windows" }
        "#microsoft.graph.winGetApp"              { $platform = "Windows" }
        "#microsoft.graph.officeSuiteApp"         { $platform = "Windows" }
        
        "#microsoft.graph.macOSLobApp"            { $platform = "macOS" }
        "#microsoft.graph.macOSMicrosoftEdgeApp"  { $platform = "macOS" }
        
        "#microsoft.graph.webApp"                 { $platform = "Web" }
        
        default                                   { $platform = "Unknown" }
    }

    return $platform
}

#--------------------------------------------------------------------------------
# Function: Get-DevicePlatform
# Determines the device platform based on a partial match in the OData type.
#--------------------------------------------------------------------------------
function Get-DevicePlatform {
    param (
        [string]$OdataType
    )

    if ($OdataType -cmatch "(?i)android") {
        return "Android"
    } elseif ($OdataType -cmatch "(?i)ios") {
        return "iOS"
    } elseif ($OdataType -cmatch "(?i)macos") {
        return "macOS"
    } elseif ($OdataType -cmatch "(?i)windows") {
        return "Windows"
    } else {
        return "Unknown"
    }
}

#--------------------------------------------------------------------------------
# Helper Function: Process-Assignment
# Consolidates the common logic for processing a single assignment.
# Parameters:
#   - policy: The policy object containing assignment details.
#   - assignment: The specific assignment to process.
#   - platform: The determined platform for the policy.
#   - groupLookup: A hashtable mapping group IDs to display names.
#   - filterLookup: A hashtable mapping filter IDs to display names.
#   - isMobileApp: (Optional) Flag to indicate mobileApps-specific behavior.
#--------------------------------------------------------------------------------
function Process-Assignment {
    param (
        [Parameter(Mandatory=$true)]
        $policy,
        [Parameter(Mandatory=$true)]
        $assignment,
        [Parameter(Mandatory=$true)]
        $platform,
        [Parameter(Mandatory=$true)]
        $groupLookup,
        [Parameter(Mandatory=$true)]
        $filterLookup,
        [Parameter(Mandatory=$false)]
        [bool]$isMobileApp = $false
    )

    # Determine the group display name based on the assignment's target type.
    if ($assignment.target.'@odata.type' -eq "#microsoft.graph.allDevicesAssignmentTarget") {
        $groupDisplayName = "All Devices"
    } elseif ($assignment.target.'@odata.type' -eq "#microsoft.graph.allLicensedUsersAssignmentTarget" -or 
              $assignment.target.'@odata.type' -eq "#microsoft.graph.allUsersAssignmentTarget") {
        $groupDisplayName = "All Users"
    } elseif ($assignment.target.groupId -and $groupLookup.ContainsKey($assignment.target.groupId)) {
        $groupDisplayName = $groupLookup[$assignment.target.groupId]
    } else {
        $groupDisplayName = ""
    }

    # Determine the filter display name if available.
    $filterDisplayName = if ($assignment.target.deviceAndAppManagementAssignmentFilterId -and $filterLookup.ContainsKey($assignment.target.deviceAndAppManagementAssignmentFilterId)) { 
        $filterLookup[$assignment.target.deviceAndAppManagementAssignmentFilterId] 
    } else { 
        "" 
    }

    # Determine the assignment type: "Exclude" if the target is an exclusion; otherwise, "Include".
    $assignmentType = if ($assignment.target.'@odata.type' -eq "#microsoft.graph.exclusionGroupAssignmentTarget") { 
        "Exclude" 
    } else { 
        "Include" 
    }

    # Build and return the processed assignment object.
    return [PSCustomObject]@{
        PolicyId          = $policy.id
        PolicyName        = if ($isMobileApp) { $policy.displayName } else { if ($policy.displayName) { $policy.displayName } else { $policy.name } }
        PolicyDescription = $policy.description
        AssignmentType    = $assignmentType
        GroupDisplayname  = $groupDisplayName
        GroupId           = $assignment.target.groupId
        FilterId          = $assignment.target.deviceAndAppManagementAssignmentFilterId
        FilterDisplayname = $filterDisplayName
        FilterType        = $assignment.target.deviceAndAppManagementAssignmentFilterType
        InstallIntent     = if ($isMobileApp) { if ($assignment.intent) { $assignment.intent } else { "" } } else { "" }
        Platform          = $platform
    }
}

#--------------------------------------------------------------------------------
# Function: Reload-Grid
# Retrieves policy data from Microsoft Graph and prepares it for display.
#--------------------------------------------------------------------------------
function Reload-Grid {
    param (
        [Parameter(Mandatory=$true)]
        [string] $type
    )

    # Determine the correct URL based on the policy type.
    if ($type -eq "mobileApps") {
        $url = "https://graph.microsoft.com/beta/deviceAppManagement/$($type)?`$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName&`$expand=assignments"
    } elseif ($type -eq "mobileAppConfigurations") {
        $url = "https://graph.microsoft.com/beta/deviceAppManagement/$($type)?`$expand=assignments"
    } elseif ($type -eq "intents") {
        $url = "https://graph.microsoft.com/beta/deviceManagement/intents?$expand=assignments"
    } else {
        $url = "https://graph.microsoft.com/beta/deviceManagement/$($type)?`$expand=assignments"
    }

    # Retrieve the policy data from Graph (supports pagination).
    $result = Get-GraphData -url $url

    #--------------------------------------------------------------------------------
    # Build lookup tables for security groups and assignment filters.
    #--------------------------------------------------------------------------------
    $allFilters = Get-AllAssignmentFilters

    $groupLookup = @{}
    foreach ($group in $global:AllSecurityGroups) { 
        $groupLookup[$group.Id] = $group.DisplayName 
    }

    $filterLookup = @{}
    foreach ($filter in $allFilters) { 
        $filterLookup[$filter.Id] = $filter.DisplayName 
    }

    # Clear the global policy data container.
    $global:AllPolicyData = @()

    #--------------------------------------------------------------------------------
    # Process each policy retrieved from Graph.
    #--------------------------------------------------------------------------------
    foreach ($policy in $result) {
        # Determine the platform for the policy based on its type and OData type.
        if ($type -eq "configurationPolicies") {
            $platform = Get-DevicePlatform -OdataType $policy.platforms
        } elseif ($type -eq "mobileApps") {
            $platform = Get-PlatformApps -odataType $policy.'@odata.type'
        } elseif ($type -eq "groupPolicyConfigurations") {
            $platform = "Windows"
        } elseif ($type -eq "deviceManagementScripts") {
            $platform = "Windows"
        } elseif ($type -eq "deviceShellScripts") {
            $platform = "macOS"
        } elseif ($type -eq "deviceCustomAttributeShellScripts") {
            $platform = "macOS"
        } elseif ($type -eq "intents") {
            $platform = "Windows"
        } else {
            $platform = Get-DevicePlatform -OdataType $policy.'@odata.type'
        }

        # Process policies based on their type.
        if ($type -eq "deviceConfigurations" -or 
            $type -eq "configurationPolicies" -or 
            $type -eq "deviceCompliancePolicies" -or 
            $type -eq "groupPolicyConfigurations" -or 
            $type -eq "deviceHealthScripts" -or 
            $type -eq "deviceManagementScripts" -or 
            $type -eq "managedAppPolicies" -or 
            $type -eq "mobileAppConfigurations" -or 
            $type -eq "deviceShellScripts" -or 
            $type -eq "deviceCustomAttributeShellScripts") {

            if ($null -ne $policy.assignments -and $policy.assignments.Count -gt 0) {
                foreach ($assignment in $policy.assignments) {
                    $global:AllPolicyData += Process-Assignment -policy $policy `
                                                                   -assignment $assignment `
                                                                   -platform $platform `
                                                                   -groupLookup $groupLookup `
                                                                   -filterLookup $filterLookup `
                                                                   -isMobileApp:$false
                }
            } else {
                $global:AllPolicyData += [PSCustomObject]@{
                    PolicyId          = $policy.id
                    PolicyName        = if ($policy.displayName) { $policy.displayName } else { $policy.name }
                    PolicyDescription = $policy.description
                    AssignmentType    = ""
                    GroupDisplayname  = ""
                    GroupId           = ""
                    FilterId          = ""
                    FilterDisplayname = ""
                    FilterType        = ""
                    InstallIntent     = ""
                    Platform          = $platform
                }
            }
        } elseif ($type -eq "mobileApps") {
            if ($null -ne $policy.assignments -and $policy.assignments.Count -gt 0) {
                foreach ($assignment in $policy.assignments) {
                    $global:AllPolicyData += Process-Assignment -policy $policy `
                                                                   -assignment $assignment `
                                                                   -platform $platform `
                                                                   -groupLookup $groupLookup `
                                                                   -filterLookup $filterLookup `
                                                                   -isMobileApp:$true
                }
            } else {
                $global:AllPolicyData += [PSCustomObject]@{
                    PolicyId          = $policy.id
                    PolicyName        = $policy.displayName
                    PolicyDescription = $policy.description
                    AssignmentType    = ""
                    GroupDisplayname  = ""
                    GroupId           = ""
                    FilterId          = ""
                    FilterDisplayname = ""
                    FilterType        = ""
                    InstallIntent     = ""
                    Platform          = $platform
                }
            }
        } elseif ($type -eq "intents") {
            $assignments = Get-GraphData -url "https://graph.microsoft.com/beta/deviceManagement/intents('$($policy.id)')/assignments"
            if ($assignments -and $assignments.Count -gt 0) {
                foreach ($assignment in $assignments) {
                    $global:AllPolicyData += Process-Assignment -policy $policy `
                                                                   -assignment $assignment `
                                                                   -platform $platform `
                                                                   -groupLookup $groupLookup `
                                                                   -filterLookup $filterLookup `
                                                                   -isMobileApp:$false
                }
            } else {
                $assignmentStatus = if ($policy.isAssigned) { "Assigned" } else { "Not Assigned" }
                $global:AllPolicyData += [PSCustomObject]@{
                    PolicyId          = $policy.id
                    PolicyName        = $policy.displayName
                    PolicyDescription = $policy.description
                    AssignmentType    = $assignmentStatus
                    GroupDisplayname  = ""
                    GroupId           = ""
                    FilterId          = ""
                    FilterDisplayname = ""
                    FilterType        = ""
                    InstallIntent     = ""
                    Platform          = $platform
                }
            }
        }
    }
    return $global:AllPolicyData
}

#--------------------------------------------------------------------------------
# Function: Load-PolicyData
# Loads policy data, updates the DataGrid UI, and manages UI element states.
#--------------------------------------------------------------------------------
function Load-PolicyData {
    param (
        [Parameter(Mandatory = $true)]
        [string] $policyType,
        
        [Parameter(Mandatory = $true)]
        [string] $loadingMessage,

        [Parameter(Mandatory = $true)]
        [string] $loadedMessage
    )

    # Update the UI to indicate loading status.
    $StatusText.Text = $loadingMessage
    $ConfigurationPoliciesButton.IsEnabled = $false
    $DeviceConfigurationButton.IsEnabled = $false
    $ComplianceButton.IsEnabled = $false
    $AdminTemplatesButton.IsEnabled = $false
    $ApplicationsButton.IsEnabled = $false
    $AppConfigButton.IsEnabled = $false
    $RemediationScriptsButton.IsEnabled = $false
    $PlatformScriptsButton.IsEnabled = $false
    $MacosScriptsButton.IsEnabled = $false
    $DeleteAssignmentButton.IsEnabled = $false
    $AddAssignmentButton.IsEnabled = $false
    $BackupButton.IsEnabled = $false
    $RestoreButton.IsEnabled = $false
    $SearchFieldComboBox.IsEnabled = $false
    $SearchBox.IsEnabled = $false
    $SearchButton.IsEnabled = $false
    $ExportToCSVButton.IsEnabled = $false
    $ExportToMDButton.IsEnabled = $false
    $RefreshButton.IsEnabled = $false
    $RenameButton.IsEnabled = $false
    $IntentsButton.IsEnabled = $false
    $DeviceCustomAttributeShellScriptsButton.IsEnabled = $false

    # Load data synchronously.
    $result = Reload-Grid -type $policyType
    # Update the DataGrid with the loaded data.
    $PolicyDataGrid.ItemsSource = @($result)
    $PolicyDataGrid.Items.Refresh()

    # Determine which columns should be visible based on the policy type.
    $InstallIntentColumn = $PolicyDataGrid.Columns | Where-Object { $_.Header -eq "Install Intent" }
    $FilterDisplayNameColumn = $PolicyDataGrid.Columns | Where-Object { $_.Header -eq "Filter Display Name" }
    $FilterTypeColumn = $PolicyDataGrid.Columns | Where-Object { $_.Header -eq "Filter Type" }

    if ($policyType -eq "mobileApps") {
        $InstallIntentColumn.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $InstallIntentColumn.Visibility = [System.Windows.Visibility]::Collapsed
    }
    if ($policyType -eq "deviceShellScripts" -or $policyType -eq "intents" -or $policyType -eq "deviceManagementScripts" -or $policyType -eq "deviceCustomAttributeShellScripts") {
        $FilterDisplayNameColumn.Visibility = [System.Windows.Visibility]::Collapsed
        $FilterTypeColumn.Visibility = [System.Windows.Visibility]::Collapsed
    } else {
        $FilterDisplayNameColumn.Visibility = [System.Windows.Visibility]::Visible
        $FilterTypeColumn.Visibility = [System.Windows.Visibility]::Visible
    }
    
    # Re-enable UI elements and update status to indicate data has been loaded.
    $StatusText.Text = $loadedMessage
    $ConfigurationPoliciesButton.IsEnabled = $true
    $DeviceConfigurationButton.IsEnabled = $true
    $ComplianceButton.IsEnabled = $true
    $AdminTemplatesButton.IsEnabled = $true
    $ApplicationsButton.IsEnabled = $true
    $AppConfigButton.IsEnabled = $true
    $PlatformScriptsButton.IsEnabled = $true
    $MacosScriptsButton.IsEnabled = $true
    $DeleteAssignmentButton.IsEnabled = $true
    $AddAssignmentButton.IsEnabled = $true
    $BackupButton.IsEnabled = $true
    $RestoreButton.IsEnabled = $true
    $SearchFieldComboBox.IsEnabled = $true
    $SearchBox.IsEnabled = $true
    $SearchButton.IsEnabled = $true
    $ExportToCSVButton.IsEnabled = $true
    $ExportToMDButton.IsEnabled = $true
    $RefreshButton.IsEnabled = $true
    $RenameButton.IsEnabled = $true
    $IntentsButton.IsEnabled = $true
    $DeviceCustomAttributeShellScriptsButton.IsEnabled = $true
    if ($policyType -eq "configurationPolicies") {
        $SecurityBaselineAnalysisButton.IsEnabled = $true
    } else {
        $SecurityBaselineAnalysisButton.IsEnabled = $false
    }
}
