<#
.SYNOPSIS
Handles the click event for the PlatformScriptsButton to load platform scripts.

.DESCRIPTION
This script is triggered when the PlatformScriptsButton is clicked. It sets the global policy type to deviceManagementScripts and calls the Load-PolicyData function to load platform scripts. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$PlatformScriptsButton.Add_Click({
    # Code to handle click event
})
#>

$PlatformScriptsButton.Add_Click({
    Write-IntuneToolkitLog "PlatformScriptsButton clicked" -component "PlatformScripts-Button" -file "PlatformScriptsButton.ps1"

    try {
        $global:CurrentPolicyType = "deviceManagementScripts"
        Write-IntuneToolkitLog "Set CurrentPolicyType to deviceManagementScripts" -component "PlatformScripts-Button" -file "PlatformScriptsButton.ps1"

        Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading platform scripts..." -loadedMessage "Platform scripts loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for deviceManagementScripts" -component "PlatformScripts-Button" -file "PlatformScriptsButton.ps1"
    } catch {
        $errorMessage = "Failed to load platform scripts. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "PlatformScripts-Button" -file "PlatformScriptsButton.ps1"
    }
})
