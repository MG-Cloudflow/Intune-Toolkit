<#
.SYNOPSIS
Handles the click event for the ApplicationsButton to load applications.

.DESCRIPTION
This script is triggered when the ApplicationsButton is clicked. It sets the global policy type to mobileApps and calls the Load-PolicyData function to load applications. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$ApplicationsButton.Add_Click({
    # Code to handle click event
})
#>

$ApplicationsButton.Add_Click({
    Write-IntuneToolkitLog "ApplicationsButton clicked" -component "Applications-Button" -file "ApplicationsButton.ps1"

    try {
        $global:CurrentPolicyType = "mobileApps"
        Write-IntuneToolkitLog "Set CurrentPolicyType to mobileApps" -component "Applications-Button" -file "ApplicationsButton.ps1"

        Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading applications..." -loadedMessage "Applications loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for mobileApps" -component "Applications-Button" -file "ApplicationsButton.ps1"
    } catch {
        $errorMessage = "Failed to load applications. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Applications-Button" -file "ApplicationsButton.ps1"
    }
})
