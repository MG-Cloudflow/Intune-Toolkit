<#
.SYNOPSIS
Fetches selected configuration policies, merges their settings, and exports the merged settings as JSON.

.DESCRIPTION
This script retrieves details for each selected configuration policy from the GridView using the Microsoft Graph API,
merging the settings arrays from each policy into one combined collection. The merged settings are then converted
to JSON and saved to a file via a Save File dialog.

.NOTES
Author: Your Name
Date: [Insert Date]

.EXAMPLE
$SecurityBaselineAnalysisButton.Add_Click({
    # Executes the Security Baseline Analysis process.
})
#>

$SecurityBaselineAnalysisButton.Add_Click({
    Write-IntuneToolkitLog "SecurityBaselineAnalysisButton clicked" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

    try {
        # Ensure at least one policy is selected
        if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Please select one or more configuration policies.", "Information")
            Write-IntuneToolkitLog "No policies selected for baseline analysis." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            return
        }
        
        Write-IntuneToolkitLog "Selected policies count: $($PolicyDataGrid.SelectedItems.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        
        # Initialize an array to hold merged settings
        $mergedSettings = @()

        # Loop through each selected policy
        foreach ($policy in $PolicyDataGrid.SelectedItems) {
            $policyId = $policy.PolicyId
            
            Write-IntuneToolkitLog "Fetching details for policy: $policyId" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            
            # Build the Graph API URL to fetch policy details with settings expanded
            $url = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policyId)?`$expand=settings"
            
            try {
                $policyDetail = Get-GraphData -url $url
            }
            catch {
                Write-IntuneToolkitLog "Error fetching policy $policyId: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                continue
            }
            
            if ($policyDetail.settings) {
                # Ensure settings is treated as an array
                if (-not ($policyDetail.settings -is [System.Array])) {
                    $policySettings = @($policyDetail.settings)
                }
                else {
                    $policySettings = $policyDetail.settings
                }
                
                if ($policySettings.Count -gt 0) {
                    Write-IntuneToolkitLog "Merging settings from policy: $($policyDetail.name) ($policyId) - Settings count: $($policySettings.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    $mergedSettings += $policySettings
                }
                else {
                    Write-IntuneToolkitLog "Policy $policyId has an empty settings array." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                }
            }
            else {
                Write-IntuneToolkitLog "Policy $policyId has no settings to merge." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        }
        
        Write-IntuneToolkitLog "Total merged settings count: $($mergedSettings.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        
        # Convert merged settings to JSON
        $mergedJson = $mergedSettings | ConvertTo-Json -Depth 10

        # Prompt the user with a Save File dialog
        $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $SaveFileDialog.Filter = "JSON files (*.json)|*.json"
        $SaveFileDialog.Title = "Save Merged Baseline Analysis As"
        $result = $SaveFileDialog.ShowDialog()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $SaveFileDialog.FileName -ne "") {
            $mergedJson | Out-File -FilePath $SaveFileDialog.FileName -Encoding UTF8
            [System.Windows.MessageBox]::Show("Baseline analysis exported successfully.", "Success")
            Write-IntuneToolkitLog "Baseline analysis exported successfully at: $($SaveFileDialog.FileName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
        else {
            [System.Windows.MessageBox]::Show("Export canceled.", "Information")
            Write-IntuneToolkitLog "Baseline analysis export canceled by user." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
    }
    catch {
        $errorMessage = "Failed to perform baseline analysis. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
    }
})
