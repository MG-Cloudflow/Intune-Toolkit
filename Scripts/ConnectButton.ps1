<#
.SYNOPSIS
Handles the click event for the ConnectButton to connect to Microsoft Graph and retrieve tenant information.

.DESCRIPTION
This script is triggered when the ConnectButton is clicked. It connects to Microsoft Graph using specified scopes, retrieves tenant and user information, and updates the UI elements accordingly. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$ConnectButton.Add_Click({
    # Code to handle click event
})
#>

# Import the external script Connect-ToMgGraph.ps1


$ConnectButton.Add_Click({
    try {
        Write-IntuneToolkitLog "Starting connection to Microsoft Graph" -component "Connect-Button" -file "ConnectButton.ps1"
        
        # Use interactive login with specific scopes
        $authParams = @{
            interactive = $true
            Scopes = @("User.Read.All", "Directory.Read.All", "DeviceManagementConfiguration.ReadWrite.All", "DeviceManagementApps.ReadWrite.All")
        }

        # Call Connect-ToMgGraph.ps1 with the interactive login and custom scopes
        .\Scripts\Connect-ToMgGraph.ps1 @authParams
        Write-IntuneToolkitLog "Successfully connected to Microsoft Graph using interactive login with specified scopes" -component "Connect-Button" -file "ConnectButton.ps1"

        # Get tenant and user information
        $tenant = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
        $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/me" -Method GET
        Write-IntuneToolkitLog "Successfully retrieved tenant information: $($tenant.value[0].displayName)" -component "Connect-Button" -file "ConnectButton.ps1"
        Write-IntuneToolkitLog "Successfully retrieved user information: $($user.userPrincipalName)" -component "Connect-Button" -file "ConnectButton.ps1"

        # Display tenant name and signed-in user
        $TenantInfo.Text = "Tenant: $($tenant.value[0].displayName) - Signed in as: $($user.userPrincipalName)"
        Write-IntuneToolkitLog "Updated TenantInfo text" -component "Connect-Button" -file "ConnectButton.ps1"

        $global:AllSecurityGroups = Get-AllSecurityGroups

        # Update UI elements
        $StatusText.Text = "Please select a policy type."
        $PolicyDataGrid.Visibility = "Visible"
        $RenameButton.IsEnabled = $true
        $DeleteAssignmentButton.IsEnabled = $true
        $AddAssignmentButton.IsEnabled = $true
        $BackupButton.IsEnabled = $true
        $RestoreButton.IsEnabled = $true
        $ConfigurationPoliciesButton.IsEnabled = $true
        $DeviceConfigurationButton.IsEnabled = $true
        $ComplianceButton.IsEnabled = $true
        $AdminTemplatesButton.IsEnabled = $true
        $ApplicationsButton.IsEnabled = $true
        $AppConfigButton.IsEnabled = $true
        $MacosScriptsButton.IsEnabled = $true
        #$RemediationScriptsButton.IsEnabled = $true
        $PlatformScriptsButton.IsEnabled = $true
        $ConnectButton.IsEnabled = $false
        $LogoutButton.IsEnabled = $true
        $RefreshButton.IsEnabled = $true
        $SearchFieldComboBox.IsEnabled = $true
        $SearchBox.IsEnabled = $true
        $SearchButton.IsEnabled = $true
        $ExportToCSVButton.IsEnabled = $true
        $ExportToMDButton.IsEnabled = $true

        Write-IntuneToolkitLog "UI elements updated successfully" -component "Connect-Button" -file "ConnectButton.ps1"

    } catch {
        $errorMessage = "Failed to connect to Microsoft Graph. Please try again. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "Connect-Button" -file "ConnectButton.ps1"
    }
})
