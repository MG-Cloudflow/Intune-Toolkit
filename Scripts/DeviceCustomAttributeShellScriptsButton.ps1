<#
.SYNOPSIS
Handles the click event for the deviceCustomAttributeShellScriptsButton to load macOS shell scripts.

.DESCRIPTION
This script is triggered when the deviceCustomAttributeShellScriptsButton is clicked. It sets the global policy type to deviceShellScripts and calls the Load-PolicyData function to load macOS shell scripts. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin
Date: 18/02/2024

.EXAMPLE
$deviceCustomAttributeShellScriptsButton.Add_Click({
    # Code to handle click event
})
#>

$deviceCustomAttributeShellScriptsButton.Add_Click({
    Write-IntuneToolkitLog "deviceCustomAttributeShellScriptsButton clicked" -component "deviceCustomAttributeShellScripts-Button" -file "deviceCustomAttributeShellScriptsButton.ps1"

    try {
        $global:CurrentPolicyType = "deviceCustomAttributeShellScripts"
        Write-IntuneToolkitLog "Set CurrentPolicyType to Custom Attribute Shell Script" -component "deviceCustomAttributeShellScripts-Button" -file "deviceCustomAttributeShellScriptsButton.ps1"

        Load-PolicyData -policyType "deviceCustomAttributeShellScripts" -loadingMessage "Loading device Custom Attribute Shell Scripts..." -loadedMessage "Custom Attribute Shell Scripts loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for Custom Attribute Shell Script" -component "deviceCustomAttributeShellScripts-Button" -file "deviceCustomAttributeShellScriptsButton.ps1"
    } catch {
        $errorMessage = "Failed to load Custom Attribute Shell Script. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "deviceCustomAttributeShellScripts-Button" -file "deviceCustomAttributeShellScriptsButton.ps1"
    }
})