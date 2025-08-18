<#
.SYNOPSIS
Handles the click event for the AutopilotProfilesButton to load Windows Autopilot deployment profiles.

.DESCRIPTION
This script is triggered when the AutopilotProfilesButton is clicked. It sets the global policy type to windowsAutopilotDeploymentProfiles
and calls the Load-PolicyData function to load the profiles. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 12/08/2025

.EXAMPLE
$AutopilotProfilesButton.Add_Click({
    # Code to handle click event
})
#>

$AutopilotProfilesButton.Add_Click({
    Write-IntuneToolkitLog "AutopilotProfilesButton clicked" -component "AutopilotProfiles-Button" -file "AutopilotProfilesButton.ps1"

    try {
        $global:CurrentPolicyType = "windowsAutopilotDeploymentProfiles"
        Write-IntuneToolkitLog "Set CurrentPolicyType to windowsAutopilotDeploymentProfiles" -component "AutopilotProfiles-Button" -file "AutopilotProfilesButton.ps1"

        Load-PolicyData -policyType "windowsAutopilotDeploymentProfiles" -loadingMessage "Loading Autopilot profiles..." -loadedMessage "Autopilot profiles loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for windowsAutopilotDeploymentProfiles" -component "AutopilotProfiles-Button" -file "AutopilotProfilesButton.ps1"
    } catch {
        $errorMessage = "Failed to load Autopilot profiles. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "AutopilotProfiles-Button" -file "AutopilotProfilesButton.ps1"
    }
})
