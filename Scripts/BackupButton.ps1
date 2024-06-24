<#
.SYNOPSIS
Handles the backup of policies for the selected policy type in the Intune Toolkit.

.DESCRIPTION
This script handles the backup of policies for the selected policy type in the Intune Toolkit.
It retrieves the current policies, converts them to JSON, and allows the user to save the backup
to a file. The script includes error handling and logging for all major actions.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$BackupButton.Add_Click({
    # Process policy backup
})
#>

$BackupButton.Add_Click({
    Write-IntuneToolkitLog "BackupButton clicked" -component "Backup-Button" -file "BackupButton.ps1"

    try {
        # Determine the policy type from the global variable
        if ($global:CurrentPolicyType -eq "mobileApps") {
            $url = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)?`$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName&`$expand=assignments"
        } else {
            $url = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)?`$expand=assignments"
        }
        Write-IntuneToolkitLog "Determined policy type: $($global:CurrentPolicyType)" -component "Backup-Button" -file "BackupButton.ps1"
        Write-IntuneToolkitLog "Fetching data from URL: $url" -component "Backup-Button" -file "BackupButton.ps1"
        
        $backup = Get-GraphData -url $url
        Write-IntuneToolkitLog "Fetched data for backup" -component "Backup-Button" -file "BackupButton.ps1"

        $jsonBackup = $backup | ConvertTo-Json -Depth 20
        Write-IntuneToolkitLog "Converted backup data to JSON" -component "Backup-Button" -file "BackupButton.ps1"

        # Save file dialog
        $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $SaveFileDialog.Filter = "JSON files (*.json)|*.json"
        $SaveFileDialog.Title = "Save Backup As"
        $SaveFileDialog.ShowDialog() | Out-Null

        if ($SaveFileDialog.FileName -ne "") {
            $jsonBackup | Out-File -FilePath $SaveFileDialog.FileName
            [System.Windows.MessageBox]::Show("Backup saved successfully.", "Success")
            Write-IntuneToolkitLog "Backup saved successfully at: $($SaveFileDialog.FileName)" -component "Backup-Button" -file "BackupButton.ps1"
        } else {
            [System.Windows.MessageBox]::Show("Backup canceled.", "Information")
            Write-IntuneToolkitLog "Backup canceled by user" -component "Backup-Button" -file "BackupButton.ps1"
        }
    } catch {
        $errorMessage = "Failed to backup policies. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "Backup-Button" -file "BackupButton.ps1"
    }
})
