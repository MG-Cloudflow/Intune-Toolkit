<#
.SYNOPSIS
Handles the click event for the RemediationScriptsButton to load remediation scripts.

.DESCRIPTION
This script is triggered when the RemediationScriptsButton is clicked. It sets the global policy type to deviceHealthScripts and calls the Load-PolicyData function to load remediation scripts. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$RemediationScriptsButton.Add_Click({
    # Code to handle click event
})
#>

$RemediationScriptsButton.Add_Click({
    Write-IntuneToolkitLog "RemediationScriptsButton clicked" -component "RemediationScripts-Button" -file "RemediationScriptsButton.ps1"

    try {
        $global:CurrentPolicyType = "deviceHealthScripts"
        Write-IntuneToolkitLog "Set CurrentPolicyType to deviceHealthScripts" -component "RemediationScripts-Button" -file "RemediationScriptsButton.ps1"

        Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading remediation scripts..." -loadedMessage "Remediation scripts loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for deviceHealthScripts" -component "RemediationScripts-Button" -file "RemediationScriptsButton.ps1"
    } catch {
        $errorMessage = "Failed to load remediation scripts. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "RemediationScripts-Button" -file "RemediationScriptsButton.ps1"
    }
})
