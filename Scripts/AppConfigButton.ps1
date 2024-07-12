<#
.SYNOPSIS
Handles the click event for the AppConfigButton to load application configuration policies.

.DESCRIPTION
This script is triggered when the AppConfigButton is clicked. It sets the global policy type to mobileAppConfigurations and calls the Load-PolicyData function to load application configuration policies. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 09/07/2024

.EXAMPLE
$AppConfigButton.Add_Click({
    # Code to handle click event
})
#>

$AppConfigButton.Add_Click({
    Write-IntuneToolkitLog "AppConfigButton clicked" -component "AppConfig-Button" -file "AppConfigButton.ps1"

    try {
        $global:CurrentPolicyType = "mobileAppConfigurations"
        Write-IntuneToolkitLog "Set CurrentPolicyType to mobileAppConfigurations" -component "AppConfig-Button" -file "AppConfigButton.ps1"

        Load-PolicyData -policyType "mobileAppConfigurations" -loadingMessage "Loading application configurations..." -loadedMessage "Application configurations loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for mobileAppConfigurations" -component "AppConfig-Button" -file "AppConfigButton.ps1"
    } catch {
        $errorMessage = "Failed to load application configurations. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "AppConfig-Button" -file "AppConfigButton.ps1"
    }
})
