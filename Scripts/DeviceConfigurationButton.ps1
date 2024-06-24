<#
.SYNOPSIS
Handles the click event for the DeviceConfigurationButton to load device configuration policies.

.DESCRIPTION
This script is triggered when the DeviceConfigurationButton is clicked. It sets the global policy type to deviceConfigurations and calls the Load-PolicyData function to load device configuration policies. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$DeviceConfigurationButton.Add_Click({
    # Code to handle click event
})
#>

$DeviceConfigurationButton.Add_Click({
    Write-IntuneToolkitLog "DeviceConfigurationButton clicked" -component "DeviceConfiguration-Button" -file "DeviceConfigurationButton.ps1"

    try {
        $global:CurrentPolicyType = "deviceConfigurations"
        Write-IntuneToolkitLog "Set CurrentPolicyType to deviceConfigurations" -component "DeviceConfiguration-Button" -file "DeviceConfigurationButton.ps1"

        Load-PolicyData -policyType "deviceConfigurations" -loadingMessage "Loading device configurations..." -loadedMessage "Device configurations loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for deviceConfigurations" -component "DeviceConfiguration-Button" -file "DeviceConfigurationButton.ps1"
    } catch {
        $errorMessage = "Failed to load device configurations. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "DeviceConfiguration-Button" -file "DeviceConfigurationButton.ps1"
    }
})
