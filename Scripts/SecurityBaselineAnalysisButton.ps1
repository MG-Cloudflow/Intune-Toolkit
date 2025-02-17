<#
.SYNOPSIS
Fetches selected configuration policies, merges their settings into a flattened array (each setting tagged with its policy),
exports the merged result as JSON, imports the Windows 24H2 baseline, compares the merged settings against the baseline,
and generates a readable Markdown report with summary statistics.

.DESCRIPTION
This script retrieves details for each selected configuration policy from the GridView using the Microsoft Graph API
(with `$expand=settings`). It then loops through each policy’s settings and creates a flattened object that includes the policy's ID,
name, and individual setting. The merged collection is exported as JSON (to C:\output\MERGED.json) for verification.
Next, the script imports the Windows 24H2 baseline from .\SupportFiles\24H2.json and loads a settings catalog.
If the catalog file (.\SupportFiles\SettingsCatalog.json) doesn’t exist, it is fetched via Graph API and saved locally.
For each baseline setting (matched by settingDefinitionId), the script checks the merged settings to determine:
  - Which baseline settings are missing.
  - For settings that are present, it lists the policies and actual values and checks whether they match the expected value.
Extra settings in the merged data that aren’t defined in the baseline are also listed.
Finally, summary statistics are calculated and prepended to a Markdown report, which is saved via a Save File dialog.
  
.NOTES
Author: Your Name
Date: [Insert Date]

.EXAMPLE
$SecurityBaselineAnalysisButton.Add_Click({
    # Executes the entire baseline analysis process.
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

        foreach ($policy in $PolicyDataGrid.SelectedItems) {
            # Use PolicyId property if available; otherwise fallback to id
            $policyId = if ($policy.PSObject.Properties["PolicyId"]) { $policy.PolicyId } else { $policy.id }
            Write-IntuneToolkitLog "Fetching details for policy: $policyId" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            
            # Build the Graph API URL to fetch policy details with settings expanded
            $url = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policyId)?`$expand=settings"
            Write-IntuneToolkitLog "Using URL: $url" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            
            try {
                $policyDetail = Invoke-MgGraphRequest -Uri $url -Method GET
                Write-IntuneToolkitLog "Policy details retrieved for $policyId" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
            catch {
                Write-IntuneToolkitLog "Error fetching policy $policyId : $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                continue
            }
            
            if ($policyDetail -and $policyDetail.settings) {
                # Ensure settings is an array; if not, wrap it in an array.
                $settingsArray = if (-not ($policyDetail.settings -is [System.Array])) { @($policyDetail.settings) } else { $policyDetail.settings }
                if ($settingsArray.Count -gt 0) {
                    Write-IntuneToolkitLog "Merging settings from policy: $($policyDetail.name) ($policyId) - Settings count: $($settingsArray.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    foreach ($setting in $settingsArray) {
                        $mergedSettings += [PSCustomObject]@{
                            PolicyId   = $policyDetail.id
                            PolicyName = $policyDetail.name
                            Setting    = $setting
                        }
                    }
                }
                else {
                    Write-IntuneToolkitLog "Policy $policyId returned an empty settings array." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                }
            }
            else {
                Write-IntuneToolkitLog "Policy $policyId has no settings to merge." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        }
        
        Write-IntuneToolkitLog "Total merged settings count: $($mergedSettings.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        
        # Export merged settings JSON for verification
        $mergedJson = $mergedSettings | ConvertTo-Json -Depth 10
        $tempOutputPath = "C:\output\MERGED.json"
        $tempOutputDir = Split-Path $tempOutputPath
        if (-not (Test-Path $tempOutputDir)) {
            New-Item -Path $tempOutputDir -ItemType Directory -Force | Out-Null
        }
        $mergedJson | Out-File -FilePath $tempOutputPath -Encoding UTF8
        Write-IntuneToolkitLog "Merged settings exported to $tempOutputPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        
        # --- Import the 24H2 Baseline ---
        $baselinePath = ".\SupportFiles\24H2.json"
        if (-not (Test-Path $baselinePath)) {
            Write-IntuneToolkitLog "Baseline file not found at $baselinePath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            [System.Windows.MessageBox]::Show("Baseline file not found at $baselinePath", "Error")
            return
        }
        $baselineContent = Get-Content $baselinePath -Raw
        $baselineData = $baselineContent | ConvertFrom-Json
        $baselineSettings = $baselineData.settings

        # --- Load or Fetch the Settings Catalog ---
        function Get-SettingDescription {
            param (
                [string]$settingId,
                [array]$Catalog
            )
            foreach ($entry in $Catalog) {
                if ($entry.id -eq $settingId) {
                    return $entry.displayName
                }
            }
            return $settingId
        }
        function Get-SettingDisplayValue {
            param (
                [string]$settingValueId,
                [array]$Catalog
            )
            foreach ($entry in $Catalog) {
                if ($entry.options) {
                    foreach ($option in $entry.options) {
                        if ($option.itemId -eq $settingValueId) {
                            return $option.displayName
                        }
                    }
                }
            }
            return $settingValueId
        }
        $catalogPath = ".\SupportFiles\SettingsCatalog.json"
        if (Test-Path $catalogPath) {
            Write-IntuneToolkitLog "Loading settings catalog from $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            $catalogContent = Get-Content $catalogPath -Raw
            $Catalog = $catalogContent | ConvertFrom-Json
        }
        else {
            Write-IntuneToolkitLog "Catalog file not found. Fetching catalog via Graph API." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            $settingsurl = "https://graph.microsoft.com/beta/deviceManagement/configurationCategories?&$filter=(platforms%20has%20'windows10')%20and%20(technologies%20has%20'mdm')"
            $Settingscatalog = Get-GraphData -url $settingsurl
            $Catalog = @()
            $Catalog += $Settingscatalog | ForEach-Object {
                $categoryId = [System.Web.HttpUtility]::UrlEncode($_.id)
                $settingchilditemurl = "https://graph.microsoft.com/beta/deviceManagement/configurationSettings?`$filter=categoryId eq '$categoryId' and visibility has 'settingsCatalog' and (applicability/platform has 'windows10') and (applicability/technologies has 'mdm')"
                Get-GraphData -url $settingchilditemurl
            }
            $CatalogJson = $Catalog | ConvertTo-Json -Depth 10
            $catalogDir = Split-Path $catalogPath
            if (-not (Test-Path $catalogDir)) {
                New-Item -Path $catalogDir -ItemType Directory -Force | Out-Null
            }
            $CatalogJson | Out-File -FilePath $catalogPath -Encoding UTF8
            Write-IntuneToolkitLog "Settings catalog saved to $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
        
        # --- Calculate Summary Statistics ---
        $totalBaselineSettings = $baselineSettings.Count
        $missingSettings = 0
        $matchesCount = 0
        $differsCount = 0

        foreach ($baseline in $baselineSettings) {
            $baselineId = $baseline.settingInstance.settingDefinitionId
            $expectedValue = $baseline.settingInstance.choiceSettingValue.value
            if ([string]::IsNullOrEmpty($expectedValue)) {
                $expectedValue = "Not Defined"
            }
            $matches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $baselineId }
            if (-not $matches -or $matches.Count -eq 0) {
                $missingSettings++
            }
            else {
                $allMatch = $true
                foreach ($match in $matches) {
                    if ($match.Setting.settingInstance.choiceSettingValue.value -ne $expectedValue) {
                        $allMatch = $false
                        break
                    }
                }
                if ($allMatch) {
                    $matchesCount++
                }
                else {
                    $differsCount++
                }
            }
        }
        $mergedIds = $mergedSettings | ForEach-Object { $_.Setting.settingInstance.settingDefinitionId } | Sort-Object -Unique
        $baselineIds = $baselineSettings | ForEach-Object { $_.settingInstance.settingDefinitionId } | Sort-Object -Unique
        $extraIds = $mergedIds | Where-Object { $_ -notin $baselineIds }
        $extraSettingsCount = $extraIds.Count

        # --- Generate Readable Markdown Report ---
        $reportLines = @()
        $reportLines += "# Security Baseline Analysis Report"
        $reportLines += ""
        $reportLines += "## Summary"
        $reportLines += ""
        $reportLines += "- Total baseline settings: $totalBaselineSettings"
        $reportLines += "- Configured settings (Matches): $matchesCount"
        $reportLines += "- Configured settings (Differ): $differsCount"
        $reportLines += "- Missing baseline settings: $missingSettings"
        $reportLines += "- Extra settings: $extraSettingsCount"
        $reportLines += ""
        $reportLines += "## Baseline Settings Comparison"
        $reportLines += ""
        $reportLines += "| Description | Expected Value | Configured Policies | Actual Values | Comparison Result |"
        $reportLines += "|-------------|----------------|---------------------|---------------|-------------------|"
        
        foreach ($baseline in $baselineSettings) {
            $baselineId = $baseline.settingInstance.settingDefinitionId
            $expectedValue = $baseline.settingInstance.choiceSettingValue.value
            if ([string]::IsNullOrEmpty($expectedValue)) { $expectedValue = "Not Defined" }
            $readableExpected = if ($Catalog.Count -gt 0) { Get-SettingDisplayValue -settingValueId $expectedValue -Catalog $Catalog } else { $expectedValue }
            $description = if ($Catalog.Count -gt 0) { Get-SettingDescription -settingId $baselineId -Catalog $Catalog } else { $baselineId }
            
            $matches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $baselineId }
            
            if (-not $matches -or $matches.Count -eq 0) {
                $reportLines += "| $description | $readableExpected | **Missing** | N/A | Missing |"
            }
            else {
                $policyList = ($matches | ForEach-Object { "$($_.PolicyName) ($($_.PolicyId))" }) -join "; "
                $actualValuesRaw = ($matches | ForEach-Object { $_.Setting.settingInstance.choiceSettingValue.value }) -join "; "
                $actualValues = if ($Catalog.Count -gt 0) { ($matches | ForEach-Object { Get-SettingDisplayValue -settingValueId $_.Setting.settingInstance.choiceSettingValue.value -Catalog $Catalog }) -join "; " } else { $actualValuesRaw }
                $allMatch = $true
                foreach ($match in $matches) {
                    if ($match.Setting.settingInstance.choiceSettingValue.value -ne $expectedValue) {
                        $allMatch = $false
                        break
                    }
                }
                $comparison = if ($allMatch) { "Matches" } else { "Differs" }
                $reportLines += "| $description | $readableExpected | $policyList | $actualValues | $comparison |"
            }
        }
        
        # --- Identify Extra Settings not in Baseline ---
        if ($extraIds.Count -gt 0) {
            $reportLines += ""
            $reportLines += "## Extra Settings (Not Defined in Baseline)"
            $reportLines += ""
            $reportLines += "| Description | Configured Policies | Actual Values |"
            $reportLines += "|-------------|---------------------|---------------|"
            foreach ($extra in $extraIds) {
                $extraMatches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $extra }
                $policyList = ($extraMatches | ForEach-Object { "$($_.PolicyName) ($($_.PolicyId))" }) -join "; "
                $actualValuesRaw = ($extraMatches | ForEach-Object { $_.Setting.settingInstance.choiceSettingValue.value }) -join "; "
                $actualValues = if ($Catalog.Count -gt 0) { ($extraMatches | ForEach-Object { Get-SettingDisplayValue -settingValueId $_.Setting.settingInstance.choiceSettingValue.value -Catalog $Catalog }) -join "; " } else { $actualValuesRaw }
                $description = if ($Catalog.Count -gt 0) { Get-SettingDescription -settingId $extra -Catalog $Catalog } else { $extra }
                $reportLines += "| $description | $policyList | $actualValues |"
            }
        }
        
        $reportContent = $reportLines -join "`r`n"
        
        # --- Save the Report using a Save File Dialog ---
        Add-Type -AssemblyName System.Windows.Forms
        $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $SaveDialog.Filter = "Markdown files (*.md)|*.md|All files (*.*)|*.*"
        $SaveDialog.Title = "Save Security Baseline Report As"
        if ($SaveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $SaveDialog.FileName -ne "") {
            $reportContent | Out-File -FilePath $SaveDialog.FileName -Encoding UTF8
            Write-IntuneToolkitLog "Security baseline report exported to $($SaveDialog.FileName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            [System.Windows.MessageBox]::Show("Security baseline report exported to $($SaveDialog.FileName)", "Success")
        }
        else {
            [System.Windows.MessageBox]::Show("Report export canceled.", "Information")
            Write-IntuneToolkitLog "Security baseline report export canceled by user." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
    }
    catch {
        $errorMessage = "Failed to perform baseline analysis. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
    }
})
