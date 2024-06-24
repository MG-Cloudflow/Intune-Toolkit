<#
.SYNOPSIS
Handles the click event for the ComplianceButton to load compliance policies.

.DESCRIPTION
This script is triggered when the ComplianceButton is clicked. It sets the global policy type to deviceCompliancePolicies and calls the Load-PolicyData function to load compliance policies. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$ComplianceButton.Add_Click({
    # Code to handle click event
})
#>

$ComplianceButton.Add_Click({
    Write-IntuneToolkitLog "ComplianceButton clicked" -component "Compliance-Button" -file "ComplianceButton.ps1"

    try {
        $global:CurrentPolicyType = "deviceCompliancePolicies"
        Write-IntuneToolkitLog "Set CurrentPolicyType to deviceCompliancePolicies" -component "Compliance-Button" -file "ComplianceButton.ps1"

        Load-PolicyData -policyType "deviceCompliancePolicies" -loadingMessage "Loading compliance policies..." -loadedMessage "Compliance policies loaded."
        Write-IntuneToolkitLog "Called Load-PolicyData for deviceCompliancePolicies" -component "Compliance-Button" -file "ComplianceButton.ps1"
    } catch {
        $errorMessage = "Failed to load compliance policies. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Compliance-Button" -file "ComplianceButton.ps1"
    }
})
