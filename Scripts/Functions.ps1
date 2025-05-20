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

#--------------------------------------------------------------------------------
# Function: Show-BaselineSelectionDialog
# This function loads a XAML-based dialog that displays a multi-select ListBox populated with the baseline items 
# provided via the -Items parameter. It logs the items passed in and the final selection for troubleshooting.
# It returns an array of the selected baseline names or $null if no selection is made
#--------------------------------------------------------------------------------

function Show-BaselineSelectionDialog {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Items,
        [string]$Title = "Select Baselines",
        [int]$Height = 400,
        [int]$Width = 400
    )

    Write-IntuneToolkitLog "Show-BaselineSelectionDialog function called with baseline items: $($Items -join ', ')" -component "Show-BaselineSelectionDialog" -file "functions.ps1"

    # Load the XAML for the selection dialog.
    $xamlPath = ".\XML\BaselineSelectionDialog.xaml"  # Ensure this path is correct
    if (-not (Test-Path $xamlPath)) {
        $errorMessage = "BaselineSelectionDialog XAML file not found at $xamlPath"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        return $null
    }

    [xml]$xaml = Get-Content $xamlPath
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    if (-not $Window) {
        $errorMessage = "Failed to load XAML from $xamlPath"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        return $null
    }

    # Set the window title and override dimensions.
    if ($Title) {
        $Window.Title = $Title
    }
    $Window.Height = $Height
    $Window.Width  = $Width

    # Retrieve UI elements.
    $BaselineListBox = $Window.FindName("BaselineListBox")
    $OkButton = $Window.FindName("OkButton")
    $CancelButton = $Window.FindName("CancelButton")

    if (-not $BaselineListBox) {
        $errorMessage = "BaselineListBox not found in XAML"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        return $null
    }
    if (-not $OkButton) {
        $errorMessage = "OkButton not found in XAML"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        return $null
    }
    if (-not $CancelButton) {
        $errorMessage = "CancelButton not found in XAML"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        return $null
    }

    Write-IntuneToolkitLog "UI elements for baseline selection loaded successfully" -component "Show-BaselineSelectionDialog" -file "functions.ps1"

    # Populate the ListBox with the provided baseline items.
    foreach ($item in $Items) {
        $listBoxItem = New-Object System.Windows.Controls.ListBoxItem
        $listBoxItem.Content = $item
        $BaselineListBox.Items.Add($listBoxItem)
    }

    # Enable multi-selection.
    $BaselineListBox.SelectionMode = 'Extended'

    # OK button event: capture the selected items, log them, and close the window.
    $OkButton.Add_Click({
        $selectedItems = @()
        foreach ($selected in $BaselineListBox.SelectedItems) {
            $selectedItems += $selected.Content
        }
        Write-IntuneToolkitLog "User selected baselines: $($selectedItems -join ', ')" -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        $Window.DialogResult = $true
        $Window.Close()
    })

    # Cancel button event: log cancellation and close the window.
    $CancelButton.Add_Click({
        Write-IntuneToolkitLog "User canceled baseline selection." -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        $Window.DialogResult = $false
        $Window.Close()
    })

    Set-WindowIcon -Window $Window
    # Show the window modally.
    $Window.ShowDialog() | Out-Null

    # Return the selected baseline names if OK was pressed and at least one item was selected.
    if ($Window.DialogResult -eq $true -and $BaselineListBox.SelectedItems.Count -gt 0) {
        $selected = $BaselineListBox.SelectedItems | ForEach-Object { $_.Content }
        Write-IntuneToolkitLog "Returning selected baselines: $($selected -join ', ')" -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        return $selected
    } else {
        Write-IntuneToolkitLog "No baseline selected or user canceled selection." -component "Show-BaselineSelectionDialog" -file "functions.ps1"
        return $null
    }
}
#--------------------------------------------------------------------------------
# Function: Show-ExportOptionsDialog
# This function loads a XAML-based dialog that displays checkboxes for Markdown and CSV export options.
# It returns an array containing "Markdown", "CSV", or both, depending on the user's selection, or $null if canceled.
#--------------------------------------------------------------------------------
function Show-ExportOptionsDialog {
    [xml]$xaml = Get-Content ".\XML\ExportOptionsDialog.xaml"
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    # Grab the controls
    $MdChk  = $Window.FindName("MdCheckbox")
    $CsvChk = $Window.FindName("CsvCheckbox")
    $OkBtn  = $Window.FindName("OkButton")
    $Cancel = $Window.FindName("CancelButton")

    # Wire up the buttons to close the window
    $OkBtn.Add_Click({
        $Window.DialogResult = $true
        $Window.Close()
    })
    $Cancel.Add_Click({
        $Window.DialogResult = $false
        $Window.Close()
    })

    # Show it modally
    Set-WindowIcon -Window $Window

    $Window.ShowDialog() | Out-Null

    # Now after it closes, read DialogResult + checkboxes
    if ($Window.DialogResult -eq $true) {
        $sel = @()
        if ($MdChk.IsChecked)  { $sel += "Markdown" }
        if ($CsvChk.IsChecked) { $sel += "CSV" }
        return $sel
    } else {
        return $null
    }
}

#--------------------------------------------------------------------------------
# Helper Function: Show-ConfirmationDialog
#--------------------------------------------------------------------------------
# Displays a confirmation dialog using a XAML-based UI and returns the user's choice.
function Show-ConfirmationDialog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SummaryText
    )

    # Define the path to the XAML file that contains the dialog layout.
    $xamlPath = ".\XML\ConfirmationDialog.xaml"
    if (-not (Test-Path $xamlPath)) {
        Write-IntuneToolkitLog "ConfirmationDialog XAML file not found at $xamlPath" `
            -component "Show-ConfirmationDialog" -file "Show-ConfirmationDialog.ps1"
        return $false
    }

    # Load the XAML content and create a Window object.
    [xml]$xaml   = Get-Content $xamlPath
    $reader      = New-Object System.Xml.XmlNodeReader $xaml
    $Window      = [Windows.Markup.XamlReader]::Load($reader)
    if (-not $Window) {
        Write-IntuneToolkitLog "Failed to load ConfirmationDialog XAML" `
            -component "Show-ConfirmationDialog" -file "Show-ConfirmationDialog.ps1"
        return $false
    }

    # Retrieve UI elements.
    $TitleTextBlock    = $Window.FindName("ModuleInstallMessage")
    $DetailsTextBlock  = $Window.FindName("DeleteDetailsTextBlock")
    $OkButton          = $Window.FindName("OKButton")
    $CopyButton        = $Window.FindName("CopyButton")
    $CancelButton      = $Window.FindName("CancelButton")

    if (-not ($TitleTextBlock -and $DetailsTextBlock -and $OkButton -and $CopyButton -and $CancelButton)) {
        Write-IntuneToolkitLog "One or more required UI elements not found in ConfirmationDialog" `
            -component "Show-ConfirmationDialog" -file "Show-ConfirmationDialog.ps1"
        return $false
    }

    # Populate the details text.
    $DetailsTextBlock.Text = $SummaryText

    # OK button: return $true
    $OkButton.Add_Click({
        Write-IntuneToolkitLog "OK clicked in ConfirmationDialog" `
            -component "Show-ConfirmationDialog" -file "Show-ConfirmationDialog.ps1"
        $Window.DialogResult = $true
        $Window.Close()
    })

    # Copy button: copy all but the last line of $SummaryText
    $CopyButton.Add_Click({
        try {
            # Split into lines, drop the last one
            $lines = $SummaryText -split "`r?`n"
            if ($lines.Count -gt 1) {
                $textToCopy = ($lines[0..($lines.Count - 2)] -join "`n")
            }
            else {
                $textToCopy = ""
            }

            Set-Clipboard -Value $textToCopy
            Write-IntuneToolkitLog "Summary (minus last line) copied to clipboard" `
                -component "Show-ConfirmationDialog" -file "Show-ConfirmationDialog.ps1"
            [System.Windows.MessageBox]::Show("Summary copied to clipboard.","Info")
        }
        catch {
            Write-IntuneToolkitLog "Failed to copy to clipboard: $_" `
                -component "Show-ConfirmationDialog" -file "Show-ConfirmationDialog.ps1"
            [System.Windows.MessageBox]::Show("Failed to copy.","Error")
        }
    })

    # Cancel button: return $false
    $CancelButton.Add_Click({
        Write-IntuneToolkitLog "Cancel clicked in ConfirmationDialog" `
            -component "Show-ConfirmationDialog" -file "Show-ConfirmationDialog.ps1"
        $Window.DialogResult = $false
        $Window.Close()
    })

    # Display the dialog
    Set-WindowIcon -Window $Window
    return $Window.ShowDialog()
}

#region Catalog Caching and Utility Functions

#--------------------------------------------------------------------------------
# Function: Build-CatalogDictionary
# This function builds a dictionary from a provided catalog array for fast lookup.
#--------------------------------------------------------------------------------
function Build-CatalogDictionary {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Catalog
    )
    # Initialize an empty hashtable to store catalog items with lowercase keys.
    $dict = @{}

    # Local helper function to recursively add catalog entries (and their children) to the dictionary.
    function Add-EntryToDict($entry) {
        if ($null -eq $entry) { return }
        # If the entry has options, iterate through each option to add them.
        if ($entry.options) {
            foreach ($option in $entry.options) {
                if ($option.itemId) {
                    $key = $option.itemId.ToLower()
                    if (-not $dict.ContainsKey($key)) {
                        $dict[$key] = $option
                    }
                }
                if ($option.name) {
                    $key = $option.name.ToLower()
                    if (-not $dict.ContainsKey($key)) {
                        $dict[$key] = $option
                    }
                }
            }
        }
        # Check for properties "id" and add to dictionary.
        if ($entry.PSObject.Properties["id"]) {
            $id = $entry.id.ToString().ToLower()
            if (-not $dict.ContainsKey($id)) {
                $dict[$id] = $entry
            }
        }
        # Check for "itemId" property and add to dictionary.
        if ($entry.PSObject.Properties["itemId"]) {
            $itemId = $entry.itemId.ToString().ToLower()
            if (-not $dict.ContainsKey($itemId)) {
                $dict[$itemId] = $entry
            }
        }
        # Check for "name" property and add to dictionary.
        if ($entry.PSObject.Properties["name"]) {
            $name = $entry.name.ToString().ToLower()
            if (-not $dict.ContainsKey($name)) {
                $dict[$name] = $entry
            }
        }
        # Recursively add any child entries if present.
        if ($entry.Children) {
            foreach ($child in $entry.Children) {
                Add-EntryToDict $child
            }
        }
    }

    # Process each entry in the provided catalog.
    foreach ($entry in $Catalog) {
        Add-EntryToDict $entry
    }
    return $dict
}

#--------------------------------------------------------------------------------
# Function: Maybe-Shorten
# This function checks if the friendly value is identical to the raw value and is too long or contains XML.
# If so, it returns a safety message.
#--------------------------------------------------------------------------------
function Maybe-Shorten {
    param (
        [Parameter(Mandatory=$true)]
        [string]$raw,
        [Parameter(Mandatory=$true)]
        [string]$friendly
    )
    # Remove any newlines and trim the friendly string.
    $friendy = ($friendy -replace "[\r\n]+", " ").Trim()
    if ($friendly.ToLower() -eq $raw.ToLower() -and $friendly.Length -gt 200 -or $friendly -contains "<?xml") {
         return "Cannot display the value in report too Long"
    }
    return $friendly
}

#--------------------------------------------------------------------------------
# Function: Find-CatalogEntry
# This function looks up an entry in the catalog dictionary by a given key.
#--------------------------------------------------------------------------------
function Find-CatalogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$CatalogDictionary,
        [Parameter(Mandatory=$true)]
        [string]$Key
    )
    $lookupKey = $Key.ToLower()
    if ($CatalogDictionary.ContainsKey($lookupKey)) {
        Write-IntuneToolkitLog "Find-CatalogEntry: Found matching entry for key '$Key'" -component "CatalogLookup" -file "SecurityBaselineAnalysisButton.ps1"
        return $CatalogDictionary[$lookupKey]
    }
    Write-IntuneToolkitLog "Find-CatalogEntry: No matching entry found for key '$Key'" -component "CatalogLookup" -file "SecurityBaselineAnalysisButton.ps1"
    return $null
}

#--------------------------------------------------------------------------------
# Function: Get-SettingDisplayValue
# This function retrieves a friendly display value for a given setting ID from the catalog.
#--------------------------------------------------------------------------------
function Get-SettingDisplayValue {
    param (
        [string]$settingValueId,
        [hashtable]$CatalogDictionary
    )
    Write-IntuneToolkitLog "Get-SettingDisplayValue: Looking up display value for '$settingValueId'" -component "CatalogLookup" -file "SecurityBaselineAnalysisButton.ps1"
    $entry = Find-CatalogEntry -CatalogDictionary $CatalogDictionary -Key $settingValueId
    if ($entry) {
        if ($entry.PSObject.Properties["displayName"] -and $entry.displayName -ne "") {
            if ($entry.displayName -eq "Top Level Setting Group Collection") {
                return $entry.name
            }
            return $entry.displayName
        }
        return $entry.name
    }
    return $settingValueId
}

#--------------------------------------------------------------------------------
# Function: Get-SettingDescription
# This function retrieves a friendly description for a given setting ID from the catalog.
#--------------------------------------------------------------------------------
function Get-SettingDescription {
    param (
        [string]$settingId,
        [hashtable]$CatalogDictionary
    )
    Write-IntuneToolkitLog "Get-SettingDescription: Looking up description for '$settingId'" -component "CatalogLookup" -file "SecurityBaselineAnalysisButton.ps1"
    $entry = Find-CatalogEntry -CatalogDictionary $CatalogDictionary -Key $settingId
    if ($entry) {
        if ($entry.PSObject.Properties["description"] -and $entry.description -ne "") {
            return ($entry.description -replace "[\r\n]+", " ").Trim()
        }
        elseif ($entry.PSObject.Properties["displayName"] -and $entry.displayName -ne "") {
            return $entry.displayName
        }
        return $entry.name
    }
    return $settingId
}

#--------------------------------------------------------------------------------
# Function: Convert-CompositeToDisplay
# This function converts a composite (group-based) raw setting ID into a friendly display format.
#--------------------------------------------------------------------------------
function Convert-CompositeToDisplay {
    param (
       [string]$RawComposite,
       [hashtable]$CatalogDictionary
    )
    # Split the composite string using the backslash separator.
    $parts = $RawComposite -split '\\'
    $displayParts = @()
    foreach ($part in $parts) {
        # Lookup each part's friendly display value.
        $displayParts += (Get-SettingDisplayValue -settingValueId $part -CatalogDictionary $CatalogDictionary).Trim()
    }
    # Rejoin the parts with a backslash.
    return ($displayParts -join "\")
}

#endregion Catalog Caching and Utility Functions

#region Flattening Functions

#--------------------------------------------------------------------------------
# Function: Flatten-GroupSetting
# This function flattens group-based baseline settings by processing each child setting individually.
#--------------------------------------------------------------------------------
function Flatten-GroupSetting {
    param (
        [string]$ParentId,
        [array]$Children,
        [string]$BaselinePolicy
    )
    $results = @()
    foreach ($child in $Children) {
        # Determine the expected value based on the type of setting value.
        if ($child.choiceSettingValue -and $child.choiceSettingValue.value) {
            $expected = "$($child.choiceSettingValue.value)"
        }
        elseif ($child.simpleSettingValue -and $child.simpleSettingValue.value) {
            $expected = "$($child.simpleSettingValue.value)"
        }
        else {
            $expected = "Not Defined"
        }
        # Build a composite description combining parent and child IDs.
        $composite = "$ParentId\$($child.settingDefinitionId)"
        Write-IntuneToolkitLog "Flattened baseline child: Composite='$composite', Expected='$expected'" -component "BaselineFlatten" -file "SecurityBaselineAnalysisButton.ps1"
        # Create a custom object for the flattened baseline setting.
        $results += [PSCustomObject]@{
            BaselinePolicy       = $BaselinePolicy
            CompositeDescription = $composite
            BaselineId           = $child.settingDefinitionId
            ExpectedValue        = $expected
        }
    }
    return $results
}

#--------------------------------------------------------------------------------
# Function: Flatten-BaselineSettings
# This function flattens baseline settings by processing each entry and handling group-based settings.
#--------------------------------------------------------------------------------
function Flatten-BaselineSettings {
    param (
        [array]$MergedBaseline
    )
    $flat = @()
    foreach ($entry in $MergedBaseline) {
        $bp = $entry.BaselinePolicy
        $bs = $entry.Setting
        # Validate that the settingInstance and its settingDefinitionId exist.
        if (-not $bs.settingInstance -or -not $bs.settingInstance.settingDefinitionId) {
            Write-IntuneToolkitLog "Baseline entry for policy '$bp' missing settingInstance or settingDefinitionId." -component "BaselineFlatten" -file "SecurityBaselineAnalysisButton.ps1"
            $flat += [PSCustomObject]@{
                BaselinePolicy       = $bp
                CompositeDescription = "(No settingInstance)"
                BaselineId           = ""
                ExpectedValue        = "Not Defined"
            }
            continue
        }
        # Check if the settingInstance is a group container.
        if ($bs.settingInstance.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance") {
            Write-IntuneToolkitLog "Processing group container for baseline policy '$bp', ParentID: $($bs.settingInstance.settingDefinitionId)" -component "BaselineFlatten" -file "SecurityBaselineAnalysisButton.ps1"
            $flat += Flatten-GroupSetting -ParentId $bs.settingInstance.settingDefinitionId -Children ($bs.settingInstance.groupSettingCollectionValue.children) -BaselinePolicy $bp
        }
        else {
            # Process a single (non-group) baseline setting.
            $baselineId = $bs.settingInstance.settingDefinitionId
            if ($bs.settingInstance.choiceSettingValue -and $bs.settingInstance.choiceSettingValue.value) {
                $expected = "$($bs.settingInstance.choiceSettingValue.value)"
            }
            elseif ($bs.settingInstance.simpleSettingValue -and $bs.settingInstance.simpleSettingValue.value) {
                $expected = "$($bs.settingInstance.simpleSettingValue.value)"
            }
            else {
                $expected = "Not Defined"
            }
            $flat += [PSCustomObject]@{
                BaselinePolicy       = $bp
                CompositeDescription = $baselineId
                BaselineId           = $baselineId
                ExpectedValue        = $expected
            }
        }
    }
    return $flat
}

#--------------------------------------------------------------------------------
# Function: Flatten-PolicySettings
# This function flattens policy settings retrieved from the Graph API, handling both single and group-based settings.
#--------------------------------------------------------------------------------
function Flatten-PolicySettings {
    param (
        [array]$MergedPolicy
    )
    $flat = @()
    foreach ($entry in $MergedPolicy) {
        $bp = $entry.PolicyName
        $ps = $entry.Setting
        # Validate that the settingInstance exists and contains a settingDefinitionId.
        if (-not $ps.settingInstance -or -not $ps.settingInstance.settingDefinitionId) {
            Write-IntuneToolkitLog "Policy entry for '$bp' missing settingInstance or settingDefinitionId." -component "PolicyFlatten" -file "SecurityBaselineAnalysisButton.ps1"
            $flat += [PSCustomObject]@{
                PolicyName           = $bp
                CompositeDescription = "(No settingInstance)"
                PolicySettingId      = ""
                ActualValue          = "Not Defined"
            }
            continue
        }
        # If the policy setting is a group container, process each child setting.
        if ($ps.settingInstance.'@odata.type' -eq "#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance") {
            Write-IntuneToolkitLog "Processing group container for policy '$bp', ParentID: $($ps.settingInstance.settingDefinitionId)" -component "PolicyFlatten" -file "SecurityBaselineAnalysisButton.ps1"
            foreach ($group in $ps.settingInstance.groupSettingCollectionValue) {
                foreach ($child in $group.children) {
                    if ($child.choiceSettingValue -and $child.choiceSettingValue.value) {
                        $actual = "$($child.choiceSettingValue.value)"
                    }
                    elseif ($child.simpleSettingValue -and $child.simpleSettingValue.value) {
                        $actual = "$($child.simpleSettingValue.value)"
                    }
                    else {
                        $actual = "Not Defined"
                    }
                    # Build a composite description for the child setting.
                    $composite = "$($ps.settingInstance.settingDefinitionId)\$($child.settingDefinitionId)"
                    Write-IntuneToolkitLog "Flattened policy child: Composite='$composite', Actual='$actual'" -component "PolicyFlatten" -file "SecurityBaselineAnalysisButton.ps1"
                    $flat += [PSCustomObject]@{
                        PolicyName           = $bp
                        CompositeDescription = $composite
                        PolicySettingId      = $child.settingDefinitionId
                        ActualValue          = $actual
                    }
                }
            }
        }
        else {
            # Process a single (non-group) policy setting.
            $policyId = $ps.settingInstance.settingDefinitionId
            if ($ps.settingInstance.choiceSettingValue -and $ps.settingInstance.choiceSettingValue.value) {
                $actual = "$($ps.settingInstance.choiceSettingValue.value)"
            }
            elseif ($ps.settingInstance.simpleSettingValue -and $ps.settingInstance.simpleSettingValue.value) {
                $actual = "$($ps.settingInstance.simpleSettingValue.value)"
            }
            else {
                $actual = "Not Defined"
            }
            $flat += [PSCustomObject]@{
                PolicyName           = $bp
                CompositeDescription = $policyId
                PolicySettingId      = $policyId
                ActualValue          = $actual
            }
        }
    }
    return $flat
}

#endregion Flattening Functions
