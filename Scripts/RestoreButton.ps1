<#
.SYNOPSIS
Handles the restoration of policies from a backup file in the Intune Toolkit.

.DESCRIPTION
This script handles the restoration of policies from a backup file in the Intune Toolkit.
It allows the user to select a backup file, reads and parses the file, and updates the
assignments for each policy in the backup. The script includes error handling and logging
for all major actions.

.NOTES
Author: Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$RestoreButton.Add_Click({
    # Process policy restoration
})
#>

$RestoreButton.Add_Click({
    Write-IntuneToolkitLog "RestoreButton clicked" -component "Restore-Button" -file "RestoreButton.ps1"

    try {
        # Open file dialog to select backup file
        $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $OpenFileDialog.Filter = "JSON files (*.json)|*.json"
        $OpenFileDialog.Title = "Select Backup File"
        $OpenFileDialog.ShowDialog() | Out-Null

        if ($OpenFileDialog.FileName -ne "") {
            Write-IntuneToolkitLog "Selected backup file: $($OpenFileDialog.FileName)" -component "Restore-Button" -file "RestoreButton.ps1"

            # Read and parse the backup file
            $backupContent = Get-Content -Path $OpenFileDialog.FileName -Raw
            Write-IntuneToolkitLog "Read backup file content" -component "Restore-Button" -file "RestoreButton.ps1"
            $backupData = $backupContent | ConvertFrom-Json
            Write-IntuneToolkitLog "Parsed backup file content to JSON" -component "Restore-Button" -file "RestoreButton.ps1"

            # Determine the policy type from the global variable
            $policyType = $global:CurrentPolicyType
            Write-IntuneToolkitLog "Determined policy type: $policyType" -component "Restore-Button" -file "RestoreButton.ps1"

            # Loop through each policy in the backup
            foreach ($policy in $backupData) {
                Write-IntuneToolkitLog "Processing policy: $($policy.id)" -component "Restore-Button" -file "RestoreButton.ps1"

                # Create the assignments body for the policy
                if ($policyType -eq "mobileApps") {
                    $bodyObject = @{
                        mobileAppAssignments = $policy.assignments
                    }
                } else {
                    $bodyObject = @{
                        assignments = $policy.assignments
                    }
                }

                # Convert the body object to a JSON string
                $body = $bodyObject | ConvertTo-Json -Depth 10
                Write-IntuneToolkitLog "Converted assignments to JSON for policy: $($policy.id)" -component "Restore-Button" -file "RestoreButton.ps1"

                # Update the assignments for the policy
                if ($policyType -eq "mobileApps") {
                    $UrlUpdateAssignments = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($policy.id)/assign"
                } else {
                    $UrlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/$($policyType)/$($policy.id)/assign"
                }
                Write-IntuneToolkitLog "Updating assignments at: $UrlUpdateAssignments" -component "Restore-Button" -file "RestoreButton.ps1"
                Invoke-MgGraphRequest -Uri $UrlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
                Write-IntuneToolkitLog "Assignments updated for policy: $($policy.id)" -component "Restore-Button" -file "RestoreButton.ps1"
            }

            [System.Windows.MessageBox]::Show("Assignments restored successfully.", "Success")
            Write-IntuneToolkitLog "Assignments restored successfully" -component "Restore-Button" -file "RestoreButton.ps1"

            # Refresh the DataGrid after restoration
            Write-IntuneToolkitLog "Refreshing DataGrid" -component "Restore-Button" -file "RestoreButton.ps1"
            Load-PolicyData -policyType $policyType -loadingMessage "Loading $($policyType)..." -loadedMessage "$($policyType) loaded."
            Write-IntuneToolkitLog "DataGrid refreshed" -component "Restore-Button" -file "RestoreButton.ps1"
        } else {
            $message = "Restore canceled."
            [System.Windows.MessageBox]::Show($message, "Information")
            Write-IntuneToolkitLog $message -component "Restore-Button" -file "RestoreButton.ps1"
        }
    } catch {
        $errorMessage = "Failed to restore assignments. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "Restore-Button" -file "RestoreButton.ps1"
    }
})
