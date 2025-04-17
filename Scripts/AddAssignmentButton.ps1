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

        # --------------------------------------------------------------------------------
        # Retrieve and prepare security groups and assignment filters.
        # --------------------------------------------------------------------------------

        Write-IntuneToolkitLog "Fetched all security groups" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
        # Clone the global security groups list to avoid modifying the original.
        $allGroups = $global:AllSecurityGroups.Clone()

        # Append special options for "All Users" and "All Devices".
        $allGroups += [PSCustomObject]@{ Id = "ALL_USERS"; Tag = "ALL_USERS"; DisplayName = "All Users" }
        $allGroups += [PSCustomObject]@{ Id = "ALL_DEVICES"; Tag = "ALL_DEVICES"; DisplayName = "All Devices" }

        # Retrieve all assignment filters.
        $allFilters = Get-AllAssignmentFilters
        Write-IntuneToolkitLog "Fetched all assignment filters" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

        # Determine whether to include intent selection based on the current policy type.
        $includeIntent = ($global:CurrentPolicyType -eq "mobileApps")

        # --------------------------------------------------------------------------------
        # Display the selection dialog for group and filter.
        # --------------------------------------------------------------------------------
        try {
            $selection = Show-SelectionDialog -groups $allGroups -filters $allFilters -includeIntent $includeIntent
        }
        catch {
            # If no selection is made, alert the user and log the event.
            $message = "No group selected. Please select a group to continue."
            [System.Windows.MessageBox]::Show($message)
            Write-IntuneToolkitLog $message -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            return
        }

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

        $summaryLines = foreach ($pol in $selectedPolicies) {
            $line = "Policy: $($pol.PolicyName) – Add to [Group: $($selection.Group.Content)]"
            if ($selection.Filter) {
                $line += " - [Filter: $($selection.Filter.Content)]"
            }
            if ($selection.FilterType) {
                $line += " - [Intent: $($selection.FilterType)]"
            }
            $line
        }
        $summaryText = "The following assignments will be added:`n`n" + ($summaryLines -join "`n")
        $summaryText += "`n`nAre you sure you want to proceed?"
        
        # Show the same confirmation dialog (you can rename it later)
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

            # --------------------------------------------------------------------------------
            # Fetch the current assignments for the selected policy based on its type.
            # --------------------------------------------------------------------------------
            if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                $urlGetAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')?`$expand=assignments"
                $application = Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET
                $assignments = $application.assignments
            }
            elseif ($global:CurrentPolicyType -eq "configurationPolicies") {
                $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assignments"
                $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value
            }
            else {
                $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')?`$expand=assignments"
                $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).assignments
            }

            Write-IntuneToolkitLog "Fetching current assignments from: $urlGetAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            Write-IntuneToolkitLog "Fetched assignments: $($assignments.Count)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            # --------------------------------------------------------------------------------
            # Determine the target type and group ID based on the user's selection.
            # --------------------------------------------------------------------------------
            switch ($selection.Group.Tag) {
                "ALL_USERS" {
                    $targetType = "#microsoft.graph.allLicensedUsersAssignmentTarget"
                    $groupId = $null
                }
                "ALL_DEVICES" {
                    $targetType = "#microsoft.graph.allDevicesAssignmentTarget"
                    $groupId = $null
                }
                default {
                    # If the assignment type is "Exclude", use the exclusion group target.
                    $targetType = if ($selection.AssignmentType -eq "Exclude") {
                        "#microsoft.graph.exclusionGroupAssignmentTarget"
                    }
                    else {
                        "#microsoft.graph.groupAssignmentTarget"
                    }
                    $groupId = $selection.Group.Tag
                }
            }

            # Build the target object with the proper OData type.
            $target = @{ '@odata.type' = $targetType }
            if ($groupId) {
                $target.groupId = $groupId
            }

            # --------------------------------------------------------------------------------
            # Build the new assignment based on the policy type.
            # --------------------------------------------------------------------------------
            if ($global:CurrentPolicyType -eq "mobileApps") {
                # For mobile apps, include the intent and potentially assignment settings.
                $newAssignment = @{
                    '@odata.type' = "#microsoft.graph.mobileAppAssignment"
                    target        = $target
                    intent        = $selection.Intent
                }

                # If a filter was selected, add filter properties.
                if ($selection.Filter) {
                    $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $selection.Filter.Tag
                    $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $selection.FilterType
                }

                # If this is not an exclusion, retrieve the appropriate settings.
                if ($selection.AssignmentType -ne "Exclude") {
                    $appODataType = $application.'@odata.type'
                    switch ($appODataType) {
                        "#microsoft.graph.androidForWorkApp"             { $settings = Get-AndroidForWorkAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.androidLobApp"                   { $settings = Get-AndroidLobAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.androidManagedStoreApp"          { $settings = Get-AndroidManagedStoreAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.androidStoreApp"                 { $settings = Get-AndroidStoreAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.iosLobApp"                       { $settings = Get-IosLobAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.iosStoreApp"                     { $settings = Get-IosStoreAppAssignmentSettings -ODataType $appODataType -Intent $selection.Intent }
                        "#microsoft.graph.iosVppApp"                       { $settings = Get-IosVppAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.macOSDmgApp"                     { $settings = Get-MacOSDmgAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.macOSLobApp"                     { $settings = Get-MacOSLobAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.macOSPkgApp"                     { $settings = Get-MacOSPkgAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.managedAndroidLobApp"            { $settings = Get-ManagedAndroidLobAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.managedIOSLobApp"                { $settings = Get-ManagedIosLobAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.managedMobileLobApp"             { $settings = Get-ManagedMobileLobAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.microsoftStoreForBusinessApp"    { $settings = Get-MicrosoftStoreForBusinessAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.win32LobApp"                     { $settings = Get-Win32LobAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.windowsAppX"                     { $settings = Get-WindowsAppXAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.windowsMobileMSI"              { $settings = Get-WindowsMobileMSIAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.windowsStoreApp"                 { $settings = Get-WindowsStoreAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.windowsUniversalAppX"            { $settings = Get-WindowsUniversalAppXAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.windowsWebApp"                   { $settings = Get-WindowsWebAppAssignmentSettings -ODataType $appODataType }
                        "#microsoft.graph.winGetApp"                       { $settings = Get-WinGetAppAssignmentSettings -ODataType $appODataType }
                        default                                          { $settings = Get-DefaultAppAssignmentSettings -ODataType $appODataType }
                    }
                    # Include the retrieved settings in the new assignment.
                    $newAssignment.settings = $settings
                }

                # Update the assignments list and create the body object for mobile apps.
                $assignments += $newAssignment
                $bodyObject = @{ mobileAppAssignments = $assignments }
            }
            # For specific script types, assign to deviceManagementScriptAssignments.
            elseif ($global:CurrentPolicyType -in @("deviceManagementScripts", "deviceShellScripts", "deviceCustomAttributeShellScripts")) {
                $newAssignment = @{ target = $target }
                if ($selection.Filter) {
                    $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $selection.Filter.Tag
                    $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $selection.FilterType
                }
                $assignments += $newAssignment
                $bodyObject = @{ deviceManagementScriptAssignments = $assignments }
            }
            # Default case for other policy types.
            else {
                $newAssignment = @{ target = $target }
                if ($selection.Filter) {
                    $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $selection.Filter.Tag
                    $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $selection.FilterType
                }
                $assignments += $newAssignment
                $bodyObject = @{ assignments = $assignments }
            }

            # --------------------------------------------------------------------------------
            # Convert the updated assignments into a JSON body.
            # --------------------------------------------------------------------------------
            $body = $bodyObject | ConvertTo-Json -Depth 10
            Write-IntuneToolkitLog "Body for update: $body" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            # --------------------------------------------------------------------------------
            # Determine the correct update URL based on the policy type.
            # --------------------------------------------------------------------------------
            if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
            }
            else {
                $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
            }
            Write-IntuneToolkitLog "Updating assignments at: $urlUpdateAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            # --------------------------------------------------------------------------------
            # Send the update request to the Graph API.
            # --------------------------------------------------------------------------------
            Invoke-MgGraphRequest -Uri $urlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
            Write-IntuneToolkitLog "Assignments updated for policy: $($selectedPolicy.PolicyId)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
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
