<#
.SYNOPSIS
Handles the addition of assignments for selected policies in the Intune Toolkit.

.DESCRIPTION
This script handles the addition of assignments for selected policies in the Intune Toolkit. 
It retrieves the current assignments, allows the user to select a group and filter, and updates 
the assignments accordingly. The script includes error handling and logging for all major actions.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

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
    Write-IntuneToolkitLog "AddAssignmentButton clicked" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

    try {
        $selectedPolicies = $PolicyDataGrid.SelectedItems
        if ($selectedPolicies.Count -gt 0) {
            Write-IntuneToolkitLog "Selected policies count: $($selectedPolicies.Count)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            # Get all security groups and filters, then allow selection
            $allGroups = Get-AllSecurityGroups
            Write-IntuneToolkitLog "Fetched all security groups" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            $allFilters = Get-AllAssignmentFilters
            Write-IntuneToolkitLog "Fetched all assignment filters" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            # Include intent selection only for mobileApps
            $includeIntent = $global:CurrentPolicyType -eq "mobileApps"
            $selection = Show-SelectionDialog -groups $allGroups -filters $allFilters -includeIntent $includeIntent
            Write-IntuneToolkitLog "Showed selection dialog" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

            if ($selection -and $selection.Group) {
                Write-IntuneToolkitLog "Selected group: $($selection.Group.Tag)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

                foreach ($selectedPolicy in $selectedPolicies) {
                    Write-IntuneToolkitLog "Processing selected policy: $($selectedPolicy.PolicyId)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

                    # Get current assignments
                    if ($global:CurrentPolicyType -eq "mobileApps") {
                        $urlGetAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$($selectedPolicy.PolicyId)')/assignments"
                    } else {
                        $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assignments"
                    }
                    Write-IntuneToolkitLog "Fetching current assignments from: $urlGetAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                    $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value
                    Write-IntuneToolkitLog "Fetched assignments: $($assignments.Count)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

                    # Determine the target type based on the assignment type
                    if ($selection.AssignmentType -eq "Exclude") {
                        $targetType = "#microsoft.graph.exclusionGroupAssignmentTarget"
                    } else {
                        $targetType = "#microsoft.graph.groupAssignmentTarget"
                    }

                    # Add the new group to the assignments
                    if ($global:CurrentPolicyType -eq "mobileApps") {
                        $newAssignment = @{
                            '@odata.type' = "#microsoft.graph.mobileAppAssignment"
                            target = @{
                                '@odata.type' = $targetType
                                groupId = $selection.Group.Tag
                            }
                            intent = $selection.Intent
                        }
                        if ($selection.Filter) {
                            $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $selection.Filter.Tag
                            $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $selection.FilterType
                        }

                        # Only add settings if it's not an exclusion
                        if ($selection.AssignmentType -ne "Exclude") {
                            $newAssignment.settings = @{
                                '@odata.type' = "#microsoft.graph.win32LobAppAssignmentSettings"
                                notifications = "showAll"
                                installTimeSettings = $null
                                restartSettings = $null
                                deliveryOptimizationPriority = "notConfigured"
                            }
                        }

                        $assignments += $newAssignment

                        # Create the body object
                        $bodyObject = @{
                            mobileAppAssignments = $assignments
                        }
                    } elseif ($global:CurrentPolicyType -eq "deviceManagementScripts") {
                        $newAssignment = @{
                            target = @{
                                '@odata.type' = $targetType
                                groupId = $selection.Group.Tag
                            }
                        }
                        if ($selection.Filter) {
                            $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $selection.Filter.Tag
                            $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $selection.FilterType
                        }
                        $assignments += $newAssignment

                        # Create the body object
                        $bodyObject = @{
                            deviceManagementScriptAssignments = $assignments
                        }
                    }else {
                        $newAssignment = @{
                            target = @{
                                '@odata.type' = $targetType
                                groupId = $selection.Group.Tag
                            }
                        }
                        if ($selection.Filter) {
                            $newAssignment.target.deviceAndAppManagementAssignmentFilterId = $selection.Filter.Tag
                            $newAssignment.target.deviceAndAppManagementAssignmentFilterType = $selection.FilterType
                        }
                        $assignments += $newAssignment

                        # Create the body object
                        $bodyObject = @{
                            assignments = $assignments
                        }
                    }

                    # Convert the body object to a JSON string
                    $body = $bodyObject | ConvertTo-Json -Depth 10
                    Write-IntuneToolkitLog "Body for update: $body" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"

                    # Update the assignments
                    if ($global:CurrentPolicyType -eq "mobileApps") {
                        $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$($selectedPolicy.PolicyId)')/assign"
                    } else {
                        $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
                    }
                    Write-IntuneToolkitLog "Updating assignments at: $urlUpdateAssignments" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                    Invoke-MgGraphRequest -Uri $urlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
                    Write-IntuneToolkitLog "Assignments updated for policy: $($selectedPolicy.PolicyId)" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                }

                # Refresh the DataGrid after adding assignments
                Write-IntuneToolkitLog "Refreshing DataGrid" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
                Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading $($global:CurrentPolicyType)..." -loadedMessage "$($global:CurrentPolicyType) loaded."
                Write-IntuneToolkitLog "DataGrid refreshed" -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            } else {
                $message = "No group selected."
                [System.Windows.MessageBox]::Show($message)
                Write-IntuneToolkitLog $message -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
            }
        } else {
            $message = "Please select one or more policies."
            [System.Windows.MessageBox]::Show($message)
            Write-IntuneToolkitLog $message -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
        }
    } catch {
        $errorMessage = "Failed to add assignments. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "AddAssignment-Button" -file "AddAssignmentButton.ps1"
    }
})
