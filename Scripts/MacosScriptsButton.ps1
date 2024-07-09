<#
.SYNOPSIS
Handles the click event for the MacosScriptsButton to load macOS shell scripts.

.DESCRIPTION
This script is triggered when the MacosScriptsButton is clicked. It sets the global policy type to deviceShellScripts and calls the Load-PolicyData function to load macOS shell scripts. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin
Date: 09/07/2024

.EXAMPLE
$MacosScriptsButton.Add_Click({
    # Code to handle click event
})
#>

$MacosScriptsButton.Add_Click({
    Write-IntuneToolkitLog "MacosScriptsButton clicked" -component "MacosScripts-Button" -file "MacosScriptsButton.ps1"

    try {
        $global:CurrentPolicyType = "deviceShellScripts"
        Write-IntuneToolkitLog "Set CurrentPolicyType to deviceShellScripts" -component "MacosScripts-Button" -file "MacosScriptsButton.ps1"

        Load-PolicyData -policyType "deviceShellScripts" -loadingMessage "Loading macOS shell scripts..." -loadedMessage "macOS shell scripts loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for deviceShellScripts" -component "MacosScripts-Button" -file "MacosScriptsButton.ps1"
    } catch {
        $errorMessage = "Failed to load macOS shell scripts. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "MacosScripts-Button" -file "MacosScriptsButton.ps1"
    }
})
