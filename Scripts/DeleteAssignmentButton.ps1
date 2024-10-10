<#
.SYNOPSIS
Handles the deletion of assignments for selected policies in the Intune Toolkit.

.DESCRIPTION
This script handles the deletion of assignments for selected policies in the Intune Toolkit.
It retrieves the current assignments, filters out the selected assignment, and updates the remaining assignments.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 09/07/2024

.EXAMPLE
$DeleteAssignmentButton.Add_Click({
    # Code to handle click event
})
#>

$DeleteAssignmentButton.Add_Click({
    Write-IntuneToolkitLog "DeleteAssignmentButton clicked" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

    try {
        $selectedPolicies = $PolicyDataGrid.SelectedItems
        if ($selectedPolicies -and $selectedPolicies.Count -gt 0) {
            Write-IntuneToolkitLog "Selected policies count: $($selectedPolicies.Count)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

            foreach ($selectedPolicy in $selectedPolicies) {
                Write-IntuneToolkitLog "Processing selected policy: $($selectedPolicy.PolicyId)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                # Get current assignments
                if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType  -eq "mobileAppConfigurations") {
                    $urlGetAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assignments"
                    $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value
                } else {
                    $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')?`$expand=assignments"
                    $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).assignments
                }
                Write-IntuneToolkitLog "Fetching current assignments from: $urlGetAssignments" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
                Write-IntuneToolkitLog "Fetched assignments: $($assignments.Count)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                # Filter out the selected group
                $updatedAssignments = @()
                foreach ($assignment in $assignments) {
                    if ($assignment.target.groupId -ne $selectedPolicy.GroupId) {
                        $assignmentObject = @{
                            target = @{
                                '@odata.type' = "#microsoft.graph.groupAssignmentTarget"
                                groupId = $assignment.target.groupId
                                deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                                deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                            }
                        }
                        # Retain original intent if it's a mobile app
                        if ($global:CurrentPolicyType -eq "mobileApps") {
                            $assignmentObject.intent = $assignment.intent
                        }
                        $updatedAssignments += $assignmentObject
                    }
                }

                Write-IntuneToolkitLog "Updated assignments count: $($updatedAssignments.Count)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                # Create the body object
                if ($global:CurrentPolicyType -eq "mobileApps") {
                    $bodyObject = @{
                        mobileAppAssignments = $updatedAssignments
                    }
                }elseif($global:CurrentPolicyType -eq "deviceManagementScripts" -or $global:CurrentPolicyType -eq "deviceShellScripts") {
                    $bodyObject = @{
                        deviceManagementScriptAssignments = $updatedAssignments
                    }
                }else {
                    $bodyObject = @{
                        assignments = $updatedAssignments
                    }
                }

                # Convert the body object to a JSON string
                $body = $bodyObject | ConvertTo-Json -Depth 10
                Write-IntuneToolkitLog "Body for update: $body" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                # Update the assignments
                if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                    $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
                } else {
                    $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
                }
                Write-IntuneToolkitLog "Updating assignments at: $urlUpdateAssignments" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
                Invoke-MgGraphRequest -Uri $urlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
                Write-IntuneToolkitLog "Assignments updated for policy: $($selectedPolicy.PolicyId)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
            }

            # Refresh the DataGrid after deletion
            Write-IntuneToolkitLog "Refreshing DataGrid" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
            Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading $($global:CurrentPolicyType)..." -loadedMessage "$($global:CurrentPolicyType) loaded."
            Write-IntuneToolkitLog "DataGrid refreshed" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
        } else {
            $message = "Please select one or more policies."
            [System.Windows.MessageBox]::Show($message)
            Write-IntuneToolkitLog $message -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
        }
    } catch {
        $errorMessage = "Failed to delete assignments. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
    }
})
