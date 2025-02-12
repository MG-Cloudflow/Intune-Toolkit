<#
.SYNOPSIS
Handles the click event for the IntentsButton to load device management intents.

.DESCRIPTION
This script is triggered when the IntentsButton is clicked. It sets the global policy type to "intents" 
and calls the Load-PolicyData function to load intents data from Microsoft Graph. Logging is implemented 
for each step along with error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 03/02/2025

.EXAMPLE
$IntentsButton.Add_Click({
    # Code to handle click event
})
#>

$IntentsButton.Add_Click({
    Write-IntuneToolkitLog "IntentsButton clicked" -component "Intents-Button" -file "IntentsButton.ps1"

    try {
        $global:CurrentPolicyType = "intents"
        Write-IntuneToolkitLog "Set CurrentPolicyType to intents" -component "Intents-Button" -file "IntentsButton.ps1"

        Load-PolicyData -policyType "intents" -loadingMessage "Loading intents..." -loadedMessage "Intents loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for intents" -component "Intents-Button" -file "IntentsButton.ps1"
    } catch {
        $errorMessage = "Failed to load intents. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Intents-Button" -file "IntentsButton.ps1"
    }
})
