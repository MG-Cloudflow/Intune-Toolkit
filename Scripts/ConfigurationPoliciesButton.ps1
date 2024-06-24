<#
.SYNOPSIS
Handles the click event for the ConfigurationPoliciesButton to load configuration policies.

.DESCRIPTION
This script is triggered when the ConfigurationPoliciesButton is clicked. It sets the global policy type to deviceConfigurations and calls the Load-PolicyData function to load configuration policies. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$ConfigurationPoliciesButton.Add_Click({
    # Code to handle click event
})
#>

$ConfigurationPoliciesButton.Add_Click({
    Write-IntuneToolkitLog "ConfigurationPoliciesButton clicked" -component "ConfigurationPolicies-Button" -file "ConfigurationPoliciesButton.ps1"

    try {
        $global:CurrentPolicyType = "configurationPolicies"
        Write-IntuneToolkitLog "Set CurrentPolicyType to configurationPolicies" -component "ConfigurationPolicies-Button" -file "ConfigurationPoliciesButton.ps1"

        Load-PolicyData -policyType "configurationPolicies" -loadingMessage "Loading configuration policies..." -loadedMessage "Configuration policies loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for configurationPolicies" -component "ConfigurationPolicies-Button" -file "ConfigurationPoliciesButton.ps1"
    } catch {
        $errorMessage = "Failed to load configuration policies. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "ConfigurationPolicies-Button" -file "ConfigurationPoliciesButton.ps1"
    }
})
