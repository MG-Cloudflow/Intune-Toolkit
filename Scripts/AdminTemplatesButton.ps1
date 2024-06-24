<#
.SYNOPSIS
Handles the click event for the AdminTemplatesButton, setting the current policy type to groupPolicyConfigurations and loading the respective policy data.

.DESCRIPTION
This script is triggered when the AdminTemplatesButton is clicked. It sets the global policy type to groupPolicyConfigurations and calls the Load-PolicyData function to load the administrative templates. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$AdminTemplatesButton.Add_Click({
    # Code to handle click event
})
#>

$AdminTemplatesButton.Add_Click({
    Write-IntuneToolkitLog "AdminTemplatesButton clicked" -component "AdminTemplates-Button" -file "AdminTemplatesButton.ps1"

    try {
        $global:CurrentPolicyType = "groupPolicyConfigurations"
        Write-IntuneToolkitLog "Set CurrentPolicyType to groupPolicyConfigurations" -component "AdminTemplates-Button" -file "AdminTemplatesButton.ps1"

        Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading administrative templates..." -loadedMessage "Administrative templates loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for groupPolicyConfigurations" -component "AdminTemplates-Button" -file "AdminTemplatesButton.ps1"
    } catch {
        $errorMessage = "Failed to load administrative templates. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "AdminTemplates-Button" -file "AdminTemplatesButton.ps1"
    }
})
