<#
.SYNOPSIS
Handles the deletion of assignments for selected policies in the Intune Toolkit.

.DESCRIPTION
This script handles the deletion of assignments for selected policies in the Intune Toolkit.
It retrieves the current assignments, filters out the selected assignment, and updates the remaining assignments.
Before deletion, a confirmation popup is shown with an overview of the assignments to be deleted.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 09/07/2024

.EXAMPLE
$DeleteAssignmentButton.Add_Click({
    # Code to handle click event
})
#>

#--------------------------------------------------------------------------------
# Main DeleteAssignmentButton Click Event
#--------------------------------------------------------------------------------
$DeleteAssignmentButton.Add_Click({
    # Log that the deletion process has been initiated.
    Write-IntuneToolkitLog "DeleteAssignmentButton clicked" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

    try {
        # Retrieve selected policies from the DataGrid.
        $selectedPolicies = $PolicyDataGrid.SelectedItems

        # Proceed only if there is at least one selected policy.
        if ($selectedPolicies -and $selectedPolicies.Count -gt 0) {
            Write-IntuneToolkitLog "Selected policies count: $($selectedPolicies.Count)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

            #--------------------------------------------------------------------------------
            # Build a summary string listing all assignments that will be deleted.
            #--------------------------------------------------------------------------------
            $summaryLines = @()
            foreach ($selectedPolicy in $selectedPolicies) {
                # Build a summary line for each policy (assuming PolicyName and GroupDisplayname properties exist).
                $line = "Policy: $($selectedPolicy.PolicyName) - Delete assignment: $($selectedPolicy.GroupDisplayname)"
                $summaryLines += $line
            }
            $summaryText = "The following assignments will be deleted:`n`n" + ($summaryLines -join "`n")
            $summaryText += "`n`nAre you sure you want to proceed?"

            #--------------------------------------------------------------------------------
            # Display the confirmation dialog and capture the user's response.
            #--------------------------------------------------------------------------------
            $confirm = Show-ConfirmationDialog -SummaryText $summaryText
            if (-not $confirm) {
                Write-IntuneToolkitLog "User canceled deletion" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
                return
            }

            #--------------------------------------------------------------------------------
            # Process each selected policy for assignment deletion.
            #--------------------------------------------------------------------------------
            foreach ($selectedPolicy in $selectedPolicies) {
                Write-IntuneToolkitLog "Processing selected policy: $($selectedPolicy.PolicyId)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                #--------------------------------------------------------------------------------
                # Retrieve the current assignments for the policy using Microsoft Graph (include Autopilot branch)
                #--------------------------------------------------------------------------------
                if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                    $urlGetAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assignments"
                    $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value
                } elseif ($global:CurrentPolicyType -eq "configurationPolicies") {
                    $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assignments"
                    $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value
                } elseif ($global:CurrentPolicyType -eq "windowsAutopilotDeploymentProfiles") {
                    $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($selectedPolicy.PolicyId)?`$expand=assignments"
                    $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).assignments
                } else {
                    $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')?`$expand=assignments"
                    $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).assignments
                }
                Write-IntuneToolkitLog "Fetching current assignments from: $urlGetAssignments" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
                Write-IntuneToolkitLog "Fetched assignments: $($assignments | ConvertTo-Json -Depth 10)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                #--------------------------------------------------------------------------------
                # Special handling for Autopilot profiles: direct DELETE per assignment id
                #--------------------------------------------------------------------------------
                if ($global:CurrentPolicyType -eq "windowsAutopilotDeploymentProfiles") {
                    $matching = @($assignments | Where-Object { $_.target.groupId -eq $selectedPolicy.GroupId })
                    if (-not $matching -or $matching.Count -eq 0) {
                        Write-IntuneToolkitLog "No matching Autopilot assignment found for groupId $($selectedPolicy.GroupId) in profile $($selectedPolicy.PolicyId)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
                        continue
                    }
                    foreach ($m in $matching) {
                        $delUrl = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($selectedPolicy.PolicyId)/assignments/$($m.id)"
                        Write-IntuneToolkitLog "Deleting Autopilot assignment via $delUrl" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
                        Invoke-MgGraphRequest -Uri $delUrl -Method DELETE
                        Write-IntuneToolkitLog "Deleted Autopilot assignment id $($m.id) for profile $($selectedPolicy.PolicyId)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
                    }
                    # Skip standard rebuild flow for this policy
                    continue
                }

                #--------------------------------------------------------------------------------
                # Filter out the assignment that matches the selected policy's GroupId (standard flow)
                #--------------------------------------------------------------------------------
                $updatedAssignments = @()
                foreach ($assignment in $assignments) {
                    if ($assignment.target.groupId -ne $selectedPolicy.GroupId) {
                        # Build an assignment object with the necessary properties.
                        $assignmentObject = @{
                            target = @{
                                '@odata.type' = $assignment.target.'@odata.type'
                                groupId = $assignment.target.groupId
                                deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                                deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                            }
                        }
                        # For mobile apps, retain the original intent.
                        if ($global:CurrentPolicyType -eq "mobileApps") {
                            $assignmentObject.intent = $assignment.intent
                        }
                        $updatedAssignments += $assignmentObject
                    }
                }
                Write-IntuneToolkitLog "Updated assignments count: $($updatedAssignments.Count)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                #--------------------------------------------------------------------------------
                # Create the body object for the update request based on policy type.
                #--------------------------------------------------------------------------------
                if ($global:CurrentPolicyType -eq "mobileApps") {
                    $bodyObject = @{
                        mobileAppAssignments = $updatedAssignments
                    }
                }
                elseif ($global:CurrentPolicyType -eq "deviceManagementScripts" -or 
                        $global:CurrentPolicyType -eq "deviceShellScripts" -or 
                        $global:CurrentPolicyType -eq "deviceCustomAttributeShellScripts") {
                    $bodyObject = @{
                        deviceManagementScriptAssignments = $updatedAssignments
                    }
                }
                else {
                    $bodyObject = @{
                        assignments = $updatedAssignments
                    }
                }

                #--------------------------------------------------------------------------------
                # Convert the body object to JSON for the API request.
                #--------------------------------------------------------------------------------
                $body = $bodyObject | ConvertTo-Json -Depth 10
                Write-IntuneToolkitLog "Body for update: $body" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                #--------------------------------------------------------------------------------
                # Determine the update URL based on the current policy type.
                #--------------------------------------------------------------------------------
                if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                    $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
                }
                else {
                    $urlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')/assign"
                }
                Write-IntuneToolkitLog "Updating assignments at: $urlUpdateAssignments" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"

                #--------------------------------------------------------------------------------
                # Send the update request to Microsoft Graph to remove the selected assignment.
                #--------------------------------------------------------------------------------
                Invoke-MgGraphRequest -Uri $urlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
                Write-IntuneToolkitLog "Assignments updated for policy: $($selectedPolicy.PolicyId)" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
            }

            #--------------------------------------------------------------------------------
            # Refresh the DataGrid to reflect the deletion.
            #--------------------------------------------------------------------------------
            Write-IntuneToolkitLog "Refreshing DataGrid" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
            Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading $($global:CurrentPolicyType)..." -loadedMessage "$($global:CurrentPolicyType) loaded."
            Write-IntuneToolkitLog "DataGrid refreshed" -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
        }
        else {
            # If no policies were selected, notify the user.
            $message = "Please select one or more policies."
            [System.Windows.MessageBox]::Show($message)
            Write-IntuneToolkitLog $message -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
        }
    }
    catch {
        # Global error handling: log and display an error message if something goes wrong.
        $errorMessage = "Failed to delete assignments. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "DeleteAssignment-Button" -file "DeleteAssignmentButton.ps1"
    }
})
