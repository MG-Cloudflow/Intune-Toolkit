<#
.SYNOPSIS
Functions for managing Microsoft Intune policies and data retrieval via Microsoft Graph API.

.DESCRIPTION
This script contains functions to manage and retrieve data related to Microsoft Intune policies. 
Functions include retrieving security groups, assignment filters, paginated data from the Graph API, 
reloading grid data, and loading policy data. Error handling and logging are implemented in each function.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$groups = Get-AllSecurityGroups
$filters = Get-AllAssignmentFilters
$data = Get-GraphData -url "https://graph.microsoft.com/beta/deviceManagement/..."
Reload-Grid -type "deviceConfigurations"
Load-PolicyData -policyType "deviceConfigurations" -loadingMessage "Loading..." -loadedMessage "Loaded."
#>

# Function to get all security groups
function Get-AllSecurityGroups {
    Write-IntuneToolkitLog "Starting Get-AllSecurityGroups" -component "Get-AllSecurityGroups" -file "Functions.ps1"
    try {
        $url = "https://graph.microsoft.com/beta/groups"
        Write-IntuneToolkitLog "Fetching all security groups with pagination from $url" -component "Get-AllSecurityGroups" -file "Functions.ps1"
        $allGroups = Get-GraphData -url $url
        $formattedGroups = $allGroups | Select-Object Id, DisplayName
        Write-IntuneToolkitLog "Successfully fetched all security groups" -component "Get-AllSecurityGroups" -file "Functions.ps1"
        return $formattedGroups
    } catch {
        $errorMessage = "Failed to get all security groups: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Get-AllSecurityGroups" -file "Functions.ps1"
    }
}

# Function to get all assignment filters
function Get-AllAssignmentFilters {
    Write-IntuneToolkitLog "Starting Get-AllAssignmentFilters" -component "Get-AllAssignmentFilters" -file "Functions.ps1"
    try {
        $url = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
        Write-IntuneToolkitLog "Fetching all assignment filters with pagination from $url" -component "Get-AllAssignmentFilters" -file "Functions.ps1"
        $allFilters = Get-GraphData -url $url
        $formattedFilters = $allFilters | ForEach-Object {
            [PSCustomObject]@{
                Id = $_.id
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

# Function to get data from Graph API with pagination
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

# Function to reload the grid data
function Reload-Grid {
    param (
        [Parameter(Mandatory=$true)]
        [string] $type
    )

    if ($type -eq "mobileApps") {
        $url = "https://graph.microsoft.com/beta/deviceAppManagement/$($type)?`$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName&`$expand=assignments"
    } else {
        $url = "https://graph.microsoft.com/beta/deviceManagement/$($type)?`$expand=assignments"
    }

    $result = Get-GraphData -url $url

    # Fetch all security groups and filters
    $allGroups = Get-AllSecurityGroups
    $allFilters = Get-AllAssignmentFilters

    # Convert lists to hash tables for quick lookup
    $groupLookup = @{}
    foreach ($group in $allGroups) {
        $groupLookup[$group.Id] = $group.DisplayName
    }

    $filterLookup = @{}
    foreach ($filter in $allFilters) {
        $filterLookup[$filter.Id] = $filter.DisplayName
    }

    # Initialize the global variable as an array
    $global:AllPolicyData = @()
    foreach ($policy in $result) {
        if ($type -eq "deviceConfigurations" -or $type -eq "configurationPolicies" -or $type -eq "deviceCompliancePolicies" -or $type -eq "groupPolicyConfigurations" -or $type -eq "deviceHealthScripts" -or $type -eq "deviceManagementScripts" -or $type -eq "managedAppPolicies") {
            if ($null -ne $policy.assignments -and $policy.assignments.Count -gt 0) {
                foreach ($assignment in $policy.assignments) {
                    $groupDisplayName = if ($assignment.target.groupId -and $groupLookup.ContainsKey($assignment.target.groupId)) { $groupLookup[$assignment.target.groupId] } else { "" }
                    $filterDisplayName = if ($assignment.target.deviceAndAppManagementAssignmentFilterId -and $filterLookup.ContainsKey($assignment.target.deviceAndAppManagementAssignmentFilterId)) { $filterLookup[$assignment.target.deviceAndAppManagementAssignmentFilterId] } else { "" }
                    $assignmentType = if ($assignment.target.'@odata.type' -eq "#microsoft.graph.exclusionGroupAssignmentTarget") { "Exclude" } else { "Include" }
                    $global:AllPolicyData += [PSCustomObject]@{
                        PolicyId = $policy.id
                        PolicyName = if ($policy.displayName) { $policy.displayName } else { $policy.name }
                        PolicyDescription = $policy.description
                        AssignmentType = $assignmentType
                        GroupDisplayname = $groupDisplayName
                        GroupId = $assignment.target.groupId
                        FilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        FilterDisplayname = $filterDisplayName
                        FilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                        InstallIntent = "" # Default empty for non-mobileApps
                    }
                }
            } else {
                $global:AllPolicyData += [PSCustomObject]@{
                    PolicyId = $policy.id
                    PolicyName = if ($policy.displayName) { $policy.displayName } else { $policy.name }
                    PolicyDescription = $policy.description
                    AssignmentType = ""
                    GroupDisplayname = ""
                    GroupId = ""
                    FilterId = ""
                    FilterDisplayname = ""
                    FilterType = ""
                    InstallIntent = "" # Default empty for non-mobileApps
                }
            }
        } elseif ($type -eq "mobileApps") {
            if ($null -ne $policy.assignments -and $policy.assignments.Count -gt 0) {
                foreach ($assignment in $policy.assignments) {
                    $groupDisplayName = if ($assignment.target.groupId -and $groupLookup.ContainsKey($assignment.target.groupId)) { $groupLookup[$assignment.target.groupId] } else { "" }
                    $filterDisplayName = if ($assignment.target.deviceAndAppManagementAssignmentFilterId -and $filterLookup.ContainsKey($assignment.target.deviceAndAppManagementAssignmentFilterId)) { $filterLookup[$assignment.target.deviceAndAppManagementAssignmentFilterId] } else { "" }
                    $assignmentType = if ($assignment.target.'@odata.type' -eq "#microsoft.graph.exclusionGroupAssignmentTarget") { "Exclude" } else { "Include" }
                    $global:AllPolicyData += [PSCustomObject]@{
                        PolicyId = $policy.id
                        PolicyName = $policy.displayName
                        PolicyDescription = $policy.description
                        AssignmentType = $assignmentType
                        GroupDisplayname = $groupDisplayName
                        GroupId = $assignment.target.groupId
                        FilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        FilterDisplayname = $filterDisplayName
                        FilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                        InstallIntent = if ($assignment.intent) { $assignment.intent } else { "" }
                    }
                }
            } else {
                $global:AllPolicyData += [PSCustomObject]@{
                    PolicyId = $policy.id
                    PolicyName = $policy.displayName
                    PolicyDescription = $policy.description
                    AssignmentType = ""
                    GroupDisplayname = ""
                    GroupId = ""
                    FilterId = ""
                    FilterDisplayname = ""
                    FilterType = ""
                    InstallIntent = ""
                }
            }
        }
    }
    return $global:AllPolicyData
}

# Function to load policy data and update the UI
function Load-PolicyData {
    param (
        [Parameter(Mandatory = $true)]
        [string] $policyType,
        
        [Parameter(Mandatory = $true)]
        [string] $loadingMessage,

        [Parameter(Mandatory = $true)]
        [string] $loadedMessage
    )

    # Update the UI to indicate loading status
    $StatusText.Text = $loadingMessage
    $ConfigurationPoliciesButton.IsEnabled = $false
    $DeviceConfigurationButton.IsEnabled = $false
    $ComplianceButton.IsEnabled = $false
    $AdminTemplatesButton.IsEnabled = $false
    $ApplicationsButton.IsEnabled = $false
    $RemediationScriptsButton.IsEnabled = $false
    $PlatformScriptsButton.IsEnabled = $false
    $DeleteAssignmentButton.IsEnabled = $false
    $AddAssignmentButton.IsEnabled = $false
    $BackupButton.IsEnabled = $false
    $RestoreButton.IsEnabled = $false
    $SearchFieldComboBox.IsEnabled = $false
    $SearchBox.IsEnabled = $false
    $SearchButton.IsEnabled = $false
    $ExportToCSVButton.IsEnabled = $false

    # Load data synchronously
    $result = Reload-Grid -type $policyType
    # Update the DataGrid with the loaded data
    $PolicyDataGrid.ItemsSource = @($result)
    $PolicyDataGrid.Items.Refresh()

    $InstallIntentColumn = $PolicyDataGrid.Columns | Where-Object { $_.Header -eq "Install Intent" }
    if ($policyType -eq "mobileApps") {
        $InstallIntentColumn.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $InstallIntentColumn.Visibility = [System.Windows.Visibility]::Collapsed
    }
    $StatusText.Text = $loadedMessage
    $ConfigurationPoliciesButton.IsEnabled = $true
    $DeviceConfigurationButton.IsEnabled = $true
    $ComplianceButton.IsEnabled = $true
    $AdminTemplatesButton.IsEnabled = $true
    $ApplicationsButton.IsEnabled = $true
    #$RemediationScriptsButton.IsEnabled = $true
    $PlatformScriptsButton.IsEnabled = $true
    $DeleteAssignmentButton.IsEnabled = $true
    $AddAssignmentButton.IsEnabled = $true
    $BackupButton.IsEnabled = $true
    $RestoreButton.IsEnabled = $true
    $SearchFieldComboBox.IsEnabled = $true
    $SearchBox.IsEnabled = $true
    $SearchButton.IsEnabled = $true
    $ExportToCSVButton.IsEnabled = $true
}