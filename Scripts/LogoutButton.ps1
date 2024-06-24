<#
.SYNOPSIS
Handles the click event for the LogoutButton to disconnect from Microsoft Graph and reset UI elements.

.DESCRIPTION
This script is triggered when the LogoutButton is clicked. It disconnects from Microsoft Graph and resets the UI elements to their default state. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$LogoutButton.Add_Click({
    # Code to handle click event
})
#>

$LogoutButton.Add_Click({
    try {
        Write-IntuneToolkitLog "Starting disconnect from Microsoft Graph" -component "Logout-Button" -file "LogoutButton.ps1"
        
        # Disconnect from Microsoft Graph
        Disconnect-MgGraph
        Write-IntuneToolkitLog "Successfully disconnected from Microsoft Graph" -component "Logout-Button" -file "LogoutButton.ps1"
        [System.Windows.MessageBox]::Show("Disconnected from Microsoft Graph.", "Success")

        # Reset UI elements
        $TenantInfo.Text = ""
        $StatusText.Text = "Please login to Graph before using the app"
        $PolicyDataGrid.Visibility = "Hidden"
        $DeleteAssignmentButton.IsEnabled = $false
        $AddAssignmentButton.IsEnabled = $false
        $BackupButton.IsEnabled = $false
        $RestoreButton.IsEnabled = $false
        $ConfigurationPoliciesButton.IsEnabled = $false
        $DeviceConfigurationButton.IsEnabled = $false
        $ComplianceButton.IsEnabled = $false
        $AdminTemplatesButton.IsEnabled = $false
        $ApplicationsButton.IsEnabled = $false
        $ConnectButton.IsEnabled = $true
        $LogoutButton.IsEnabled = $false
        $SearchFieldComboBox.IsEnabled = $false
        $SearchBox.IsEnabled = $false
        $SearchButton.IsEnabled = $false

        Write-IntuneToolkitLog "UI elements reset successfully" -component "Logout-Button" -file "LogoutButton.ps1"
        
    } catch {
        $errorMessage = "Failed to disconnect from Microsoft Graph. Please try again. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "Logout-Button" -file "LogoutButton.ps1"
    }
})
