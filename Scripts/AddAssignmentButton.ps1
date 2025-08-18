<#
.SYNOPSIS
Handles the addition of assignments for selected policies in the Intune Toolkit.

.DESCRIPTION
This script handles the addition of assignments for selected policies in the Intune Toolkit. 
It retrieves the current assignments, allows the user to select a group and filter, and updates 
the assignments accordingly. The script includes error handling and logging for all major actions.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 12/02/2025

.EXAMPLE
$AddAssignmentButton.Add_Click({
    $selectedPolicies = $PolicyDataGrid.SelectedItems
    if ($selectedPolicies.Count -gt 0) {
        # Process assignments addition
    } else {
        [System.Windows.MessageBox]::Show("Please select one or more policies.")
    }
})
#>

$AddAssignmentButton.Add_Click({
    # Log the button click event.
    Write-IntuneToolkitLog "AddAssignmentButton clicked" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

    try {
        # Retrieve selected policies from the DataGrid and sort them uniquely by PolicyId.
        $selectedPolicies = $PolicyDataGrid.SelectedItems | Sort-Object -Unique -Property PolicyId

        # If no policies are selected, notify the user and exit.
        if ($selectedPolicies.Count -le 0) {
            $message = "Please select one or more policies."
            [System.Windows.MessageBox]::Show($message)
            Write-IntuneToolkitLog $message -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            return
        }

        Write-IntuneToolkitLog "Selected policies count: $($selectedPolicies.Count)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

        if ($global:CurrentPolicyType -eq "mobileApps") {
            # Check for unique @odata.type among selected policies
            $distinctODataTypes = @()
            foreach ($pol in $selectedPolicies) {
                $url = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$($pol.PolicyId)')"
                $appObj = Invoke-MgGraphRequest -Uri $url -Method GET
                $distinctODataTypes += $appObj.'@odata.type'
            }
            $distinctODataTypes = $distinctODataTypes | Sort-Object -Unique
            if ($distinctODataTypes.Count -gt 1) {
                [System.Windows.MessageBox]::Show(
                    "You can only select one application type at a time. Please adjust your selection.",
                    "Multiple Application Types Selected",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                Write-IntuneToolkitLog "User attempted to select multiple application types at once." -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                return
            }
        }

        # --------------------------------------------------------------------------------
        # Retrieve and prepare security groups and assignment filters.
        # --------------------------------------------------------------------------------

        Write-IntuneToolkitLog "Fetched all security groups" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
        # Make sure we always have an array of groups, even if there's just one or none.
        $allGroups = @($global:AllSecurityGroups)

        # Append special options for "All Users" and "All Devices".
        $allGroups += [PSCustomObject]@{ Id = "ALL_USERS"; Tag = "ALL_USERS"; DisplayName = "All Users" }
        $allGroups += [PSCustomObject]@{ Id = "ALL_DEVICES"; Tag = "ALL_DEVICES"; DisplayName = "All Devices" }

        # Retrieve all assignment filters.
        $allFilters = Get-AllAssignmentFilters
        Write-IntuneToolkitLog "Fetched all assignment filters" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

        # Determine whether to include intent selection based on the current policy type.
        $includeIntent = ($global:CurrentPolicyType -eq "mobileApps")

        # Prepare appODataType only for mobileApps
        $appODataType = $null
        if ($global:CurrentPolicyType -eq "mobileApps" -and $selectedPolicies.Count -ge 1) {
            $firstPolicy = $selectedPolicies[0]
            $url = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$($firstPolicy.PolicyId)')"
            $appObj = Invoke-MgGraphRequest -Uri $url -Method GET
            $appODataType = $appObj.'@odata.type'
        }

        # --------------------------------------------------------------------------------
        # Display the selection dialog for group and filter.
        # --------------------------------------------------------------------------------
        $assignments = @()
        do {
            try {
                if ($global:CurrentPolicyType -eq "mobileApps") {
                    $selection = Show-SelectionDialog -groups $allGroups -filters $allFilters -includeIntent $includeIntent -appODataType $appODataType
                } else {
                    $selection = Show-SelectionDialog -groups $allGroups -filters $allFilters -includeIntent $includeIntent
                }
            }
            catch {
                $message = "No group selected. Please select a group to continue."
                [System.Windows.MessageBox]::Show($message)
                Write-IntuneToolkitLog $message -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                return
            }

            # Only add if a group was selected
            if ($selection -and $selection.Group) {
                $assignments += $selection
            }
        } while ($selection -and $selection.DialogResult -eq "AddExtra")


        # Validate the selection.
        if (-not $selection -or -not $selection.Group) {
            $message = "No group selected. Please select a group to continue."
            [System.Windows.MessageBox]::Show($message)
            Write-IntuneToolkitLog $message -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            return
        }

        Write-IntuneToolkitLog "Showed selection dialog" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
        Write-IntuneToolkitLog "Selected group: $($selection.Group.Tag)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
        #--------------------------------------------------------------------------------
        # Build a summary string listing all assignments that will be Assigned.
        #--------------------------------------------------------------------------------
        # Remove any assignments where Group is null or empty
        $assignments = $assignments | Where-Object { $_.Group -and $_.Group.Content -ne "" }
        $summaryLines = foreach ($sel in $assignments) {
            foreach ($pol in $selectedPolicies) {
                $line = "Policy: $($pol.PolicyName) – Add to [Group: $($sel.Group.Content)]"
                if ($sel.Filter) {
                    $line += " - [Filter: $($sel.Filter.Content)]"
                }
                if ($sel.FilterType) {
                    $line += " - [Filter Type: $($sel.FilterType)]"
                }
                $line
            }
        }
        $summaryText = "The following assignments will be added:`n`n" + ($summaryLines -join "`n")
        $summaryText += "`n`nAre you sure you want to proceed?"

        $confirm = Show-ConfirmationDialog -SummaryText $summaryText
        if (-not $confirm) {
            Write-IntuneToolkitLog "User canceled add assignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            return
        }

        # --------------------------------------------------------------------------------
        # Process each selected policy.
        # --------------------------------------------------------------------------------
        foreach ($selectedPolicy in $selectedPolicies) {
            Write-IntuneToolkitLog "Processing selected policy: $($selectedPolicy.PolicyId)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            # Fetch current assignments unless Autopilot (not required for Autopilot profile assignment POST)
            if ($global:CurrentPolicyType -eq "windowsAutopilotDeploymentProfiles") {
                Write-IntuneToolkitLog "Skipping fetch of existing assignments for Autopilot profile $($selectedPolicy.PolicyId)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                $currentAssignments = @()  # Not used; single POST per new assignment
            }
            elseif ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                $urlGetAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')?`$expand=assignments"
                $application = Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET
                $existingAssignments = $application.assignments
                $currentAssignments = @($existingAssignments)
                Write-IntuneToolkitLog "Fetching current assignments from: $urlGetAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                Write-IntuneToolkitLog "Fetched assignments: $($currentAssignments.Count)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            }
            elseif ($global:CurrentPolicyType -eq "configurationPolicies") {
                $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assignments"
                $existingAssignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value
                $currentAssignments = @($existingAssignments)
                Write-IntuneToolkitLog "Fetching current assignments from: $urlGetAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                Write-IntuneToolkitLog "Fetched assignments: $($currentAssignments.Count)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            }
            else {
                $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')?`$expand=assignments"
                $existingAssignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).assignments
                $currentAssignments = @($existingAssignments)
                Write-IntuneToolkitLog "Fetching current assignments from: $urlGetAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                Write-IntuneToolkitLog "Fetched assignments: $($currentAssignments.Count)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            }

            foreach ($sel in $assignments) {
                # Determine the target type and group ID based on the user's selection.
                switch ($sel.Group.Tag) {
                    "ALL_USERS" {
                        if ($global:CurrentPolicyType -eq "windowsAutopilotDeploymentProfiles") {
                            [System.Windows.MessageBox]::Show("'All Users' not supported for Autopilot profile assignments. Skipping.") | Out-Null
                            Write-IntuneToolkitLog "Skipped unsupported All Users assignment for Autopilot profile" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                            continue
                        }
                        $targetType = "#microsoft.graph.allLicensedUsersAssignmentTarget"
                        $groupId = $null
                    }
                    "ALL_DEVICES" {
                        if ($global:CurrentPolicyType -eq "windowsAutopilotDeploymentProfiles") {
                            [System.Windows.MessageBox]::Show("'All Devices' not supported for Autopilot profile assignments. Skipping.") | Out-Null
                            Write-IntuneToolkitLog "Skipped unsupported All Devices assignment for Autopilot profile" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                            continue
                        }
                        $targetType = "#microsoft.graph.allDevicesAssignmentTarget"
                        $groupId = $null
                    }
                    default {
                        $targetType = if ($sel.AssignmentType -eq "Exclude") {
                            "#microsoft.graph.exclusionGroupAssignmentTarget"
                        } else {
                            "#microsoft.graph.groupAssignmentTarget"
                        }
                        $groupId = $sel.Group.Tag
                    }
                }

                # Autopilot profiles: direct POST to /assignments per new target, no batching, no /assign endpoint
                if ($global:CurrentPolicyType -eq "windowsAutopilotDeploymentProfiles") {
                    $target = @{ '@odata.type' = $targetType }
                    if ($groupId) { $target.groupId = $groupId }
                    $bodyObject = @{ target = $target }
                    $body = $bodyObject | ConvertTo-Json -Depth 6
                    $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($selectedPolicy.PolicyId)/assignments"
                    Write-IntuneToolkitLog "Adding Autopilot assignment at: $urlUpdateAssignments with body: $body" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                    Invoke-MgGraphRequest -Uri $urlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
                    Write-IntuneToolkitLog "Autopilot assignment added for profile $($selectedPolicy.PolicyId)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                    continue
                }

                # Existing logic for other policy types
                # Build the target object with the proper OData type.
                $target = @{ '@odata.type' = $targetType }
                if ($groupId) { $target.groupId = $groupId }

                # Build the new assignment based on the policy type.
                if ($global:CurrentPolicyType -eq "mobileApps") {
                    $newAssignment = @{
                        '@odata.type' = "#microsoft.graph.mobileAppAssignment"
                        target        = $target
                        intent        = $sel.Intent
                    }

                    if ($sel.Filter) {
                        $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $sel.Filter.Tag
                        $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $sel.FilterType
                    }

                    if ($sel.AssignmentType -ne "Exclude") {
                        $appODataType = $application.'@odata.type'
                        switch ($appODataType) {
                            "#microsoft.graph.androidForWorkApp"             { $settings = Get-AndroidForWorkAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.androidLobApp"                 { $settings = Get-AndroidLobAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.androidManagedStoreApp"        { $settings = Get-AndroidManagedStoreAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.androidStoreApp"               { $settings = Get-AndroidStoreAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.iosLobApp"                     { $settings = Get-IosLobAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.iosStoreApp"                   { $settings = Get-IosStoreAppAssignmentSettings -ODataType $appODataType -Intent $sel.Intent }
                            "#microsoft.graph.iosVppApp"                     { $settings = Get-IosVppAppAssignmentSettings -ODataType $appODataType -Intent $sel.Intent }
                            "#microsoft.graph.macOSDmgApp"                   { $settings = Get-MacOSDmgAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.macOSLobApp"                   { $settings = Get-MacOSLobAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.macOSPkgApp"                   { $settings = Get-MacOSPkgAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.managedAndroidLobApp"          { $settings = Get-ManagedAndroidLobAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.managedIOSLobApp"              { $settings = Get-ManagedIosLobAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.managedMobileLobApp"           { $settings = Get-ManagedMobileLobAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.microsoftStoreForBusinessApp"  { $settings = Get-MicrosoftStoreForBusinessAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.win32LobApp"                   { $settings = Get-Win32LobAppAssignmentSettings -ODataType $appODataType -notifications $sel.Notifications -deliveryOptimizationPriority $sel.DeliveryOptimizationPriority }
                            "#microsoft.graph.windowsAppX"                   { $settings = Get-WindowsAppXAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.windowsMobileMSI"              { $settings = Get-WindowsMobileMSIAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.windowsStoreApp"               { $settings = Get-WindowsStoreAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.windowsUniversalAppX"          { $settings = Get-WindowsUniversalAppXAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.windowsWebApp"                 { $settings = Get-WindowsWebAppAssignmentSettings -ODataType $appODataType }
                            "#microsoft.graph.winGetApp"                     { $settings = Get-WinGetAppAssignmentSettings -ODataType $appODataType }
                            default                                          { $settings = Get-DefaultAppAssignmentSettings -ODataType $appODataType }
                        }
                        $newAssignment.settings = $settings
                    }

                    $currentAssignments += $newAssignment
                    $bodyObject = @{ mobileAppAssignments = $currentAssignments }
                }
                elseif ($global:CurrentPolicyType -in @("deviceManagementScripts", "deviceShellScripts", "deviceCustomAttributeShellScripts")) {
                    $newAssignment = @{ target = $target }
                    if ($sel.Filter) {
                        $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $sel.Filter.Tag
                        $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $sel.FilterType
                    }
                    $currentAssignments += $newAssignment
                    $bodyObject = @{ deviceManagementScriptAssignments = $currentAssignments }
                }
                else {
                    $newAssignment = @{ target = $target }
                    if ($sel.Filter) {
                        $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $sel.Filter.Tag
                        $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $sel.FilterType
                    }
                    $currentAssignments += $newAssignment
                    $bodyObject = @{ assignments = $currentAssignments }
                }

                # Convert the updated assignments into a JSON body.
                $body = $bodyObject | ConvertTo-Json -Depth 10
                Write-IntuneToolkitLog "Body for update: $body" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

                # Determine the correct update URL based on the policy type.
                if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                    $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
                }
                else {
                    $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
                }
                Write-IntuneToolkitLog "Updating assignments at: $urlUpdateAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

                # Send the update request to the Graph API.
                Invoke-MgGraphRequest -Uri $urlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
                Write-IntuneToolkitLog "Assignments updated for policy: $($selectedPolicy.PolicyId)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            }
        }
        # --------------------------------------------------------------------------------
        # Refresh the DataGrid after processing all assignments.
        # --------------------------------------------------------------------------------
        Write-IntuneToolkitLog "Refreshing DataGrid" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
        Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading $($global:CurrentPolicyType)..." -loadedMessage "$($global:CurrentPolicyType) loaded."
        Write-IntuneToolkitLog "DataGrid refreshed" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
    }
    catch {
        # Global error handling: log and display an error message if something goes wrong.
        $errorMessage = "Failed to add assignments. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
    }
})
