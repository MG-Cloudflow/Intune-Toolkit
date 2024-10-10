<#
.SYNOPSIS
Handles the click event for the RefreshButton to load compliance policies and security groups.

.DESCRIPTION
This script is triggered when the RefreshButton is clicked. It sets the global policy type to deviceCompliancePolicies, calls the Load-PolicyData function to load compliance policies, and retrieves all security groups. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 10/10/2024

.EXAMPLE
$RefreshButton.Add_Click({
    # Code to handle click event
})
#>
$RefreshButton.Add_Click({
    Write-IntuneToolkitLog "RefreshButton clicked" -component "Refresh-Button" -file "RefreshButton.ps1"

    try {
        $global:AllSecurityGroups = Get-AllSecurityGroups
        Write-IntuneToolkitLog "Retrieved all security groups" -component "Refresh-Button" -file "RefreshButton.ps1"

        Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading compliance policies..." -loadedMessage "Compliance policies loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for $global:CurrentPolicyType" -component "Refresh-Button" -file "RefreshButton.ps1"

    } catch {
        $errorMessage = "Failed to Refresh Secruity Groups And policy's. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Refresh-Button" -file "RefreshButton.ps1"
    }
})