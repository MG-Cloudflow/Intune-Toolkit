<#
.SYNOPSIS
Performs a detailed security baseline analysis by retrieving configuration policy settings,
merging them, dynamically selecting and merging baseline settings from one or more selected
baseline folders, comparing the two sets, and generating a Markdown report.

.DESCRIPTION
Triggered via a UI button click, the script:
  - Validates that one or more configuration policies are selected.
  - Retrieves policy details (with expanded settings) via the Microsoft Graph API.
  - Merges all policy settings into a single collection.
  - Scans the baseline root folder (".\SupportFiles\Intune Baselines") to find available baseline folders.
  - If multiple baseline folders exist, it calls the Show-BaselineSelectionDialog function (from functions.ps1)
    to allow the user to select one or more baselines.
  - For each selected baseline folder, it looks for a "SettingsCatalog" subfolder and reads the JSON files within.
  - Merges all baseline settings (tagged with their source baseline name).
  - Loads (or fetches) a human-readable settings catalog (from ".\SupportFiles\SettingsCatalog.json")
    for descriptions and display values.
  - Compares the merged baseline settings against the merged policy settings, calculating summary
    statistics (matches, differences, missing and extra settings).
  - Generates a Markdown report including the baseline policy names.
  - Prompts the user to save the report via a Save File dialog.
Extensive try/catch blocks and detailed logging (using Write-IntuneToolkitLog) are used throughout.

.NOTES
Author: Your Name
Date: [Insert Date]

.EXAMPLE
$SecurityBaselineAnalysisButton.Add_Click({
    # Executes the baseline analysis with detailed logging and error handling.
})
#>

$SecurityBaselineAnalysisButton.Add_Click({
    try {
        Write-IntuneToolkitLog "SecurityBaselineAnalysisButton clicked" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        # ---------------------------------------------------------------------------
        # Validate that at least one policy is selected in the UI.
        # ---------------------------------------------------------------------------
        try {
            if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
                Write-IntuneToolkitLog "No policies selected for baseline analysis." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                [System.Windows.MessageBox]::Show("Please select one or more configuration policies.", "Information")
                return
            }
            Write-IntuneToolkitLog "Selected policies count: $($PolicyDataGrid.SelectedItems.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        } catch {
            Write-IntuneToolkitLog "Error validating policy selection: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            throw
        }

        # ---------------------------------------------------------------------------
        # Fetch and merge policy settings via Graph API.
        # ---------------------------------------------------------------------------
        $mergedSettings = @()
        foreach ($policy in $PolicyDataGrid.SelectedItems) {
            try {
                $policyId = if ($policy.PSObject.Properties["PolicyId"]) { $policy.PolicyId } else { $policy.id }
                Write-IntuneToolkitLog "Fetching details for policy: $policyId" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                $url = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policyId)?`$expand=settings"
                Write-IntuneToolkitLog "Using URL: $url" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                try {
                    $policyDetail = Invoke-MgGraphRequest -Uri $url -Method GET
                    Write-IntuneToolkitLog "Policy details retrieved for $policyId" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                } catch {
                    Write-IntuneToolkitLog "Error fetching policy $policyId : $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    continue
                }
                if ($policyDetail -and $policyDetail.settings) {
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
            } catch {
                Write-IntuneToolkitLog "Error processing policy $($policy.id): $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        }
        Write-IntuneToolkitLog "Total merged settings count: $($mergedSettings.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        # ---------------------------------------------------------------------------
        # Locate baseline folders under the baseline root.
        # ---------------------------------------------------------------------------
        try {
            $baselineRootPath = ".\SupportFiles\Intune Baselines"
            if (-not (Test-Path $baselineRootPath)) {
                throw "Baseline folder not found at $baselineRootPath"
            }
            Write-IntuneToolkitLog "Baseline root path found: $baselineRootPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        } catch {
            Write-IntuneToolkitLog "Error locating baseline folder: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            [System.Windows.MessageBox]::Show("Baseline folder not found at $baselineRootPath", "Error")
            return
        }

        try {
            $baselineFolders = Get-ChildItem -Path $baselineRootPath -Directory
            if ($baselineFolders.Count -eq 0) {
                throw "No baseline folders found in $baselineRootPath"
            }
            Write-IntuneToolkitLog "Found $($baselineFolders.Count) baseline folder(s) in $baselineRootPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        } catch {
            Write-IntuneToolkitLog "Error retrieving baseline folders: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            [System.Windows.MessageBox]::Show("No baseline folders found", "Error")
            return
        }

        # ---------------------------------------------------------------------------
        # Baseline selection using Show-BaselineSelectionDialog from functions.ps1.
        # ---------------------------------------------------------------------------
        try {
            if ($baselineFolders.Count -gt 1) {
                $selectedBaselineNames = Show-BaselineSelectionDialog -Items ($baselineFolders | ForEach-Object { $_.Name })
                if (-not $selectedBaselineNames) {
                    throw "User cancelled baseline selection or no baseline selected."
                }
                $selectedBaselineFolders = $baselineFolders | Where-Object { $selectedBaselineNames -contains $_.Name }
                Write-IntuneToolkitLog "User selected baseline(s): $($selectedBaselineNames -join ', ')" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            } else {
                $selectedBaselineFolders = $baselineFolders
                Write-IntuneToolkitLog "Only one baseline folder found: $($baselineFolders[0].Name)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        } catch {
            Write-IntuneToolkitLog "Error during baseline selection: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            return
        }

        # ---------------------------------------------------------------------------
        # Merge Settings Catalogs from each selected baseline folder.
        # ---------------------------------------------------------------------------
        $mergedBaselineSettings = @()
        foreach ($folder in $selectedBaselineFolders) {
            try {
                Write-IntuneToolkitLog "Attempting to read JSON files from baseline folder: $($folder.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                $settingsCatalogPath = Join-Path -Path $folder.FullName -ChildPath "SettingsCatalog"
                if (-not (Test-Path $settingsCatalogPath)) {
                    Write-IntuneToolkitLog "SettingsCatalog folder not found for baseline: $($folder.Name) at expected path: $settingsCatalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    continue
                }
                Write-IntuneToolkitLog "Processing baseline folder: $($folder.Name) with catalog path: $settingsCatalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                $catalogFiles = Get-ChildItem -Path $settingsCatalogPath -Filter *.json
                foreach ($file in $catalogFiles) {
                    try {
                        Write-IntuneToolkitLog "Attempting to load JSON file: $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        $jsonContent = Get-Content $file.FullName -Raw | ConvertFrom-Json
                        Write-IntuneToolkitLog "Loaded JSON from file: $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    } catch {
                        Write-IntuneToolkitLog "Error parsing JSON in file $($file.FullName): $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        continue
                    }
                    if ($jsonContent.settings) {
                        foreach ($setting in $jsonContent.settings) {
                            $mergedBaselineSettings += [PSCustomObject]@{
                                BaselinePolicy = $folder.Name
                                Setting        = $setting
                            }
                        }
                        Write-IntuneToolkitLog "Merged settings from file: $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    } else {
                        Write-IntuneToolkitLog "No 'settings' property found in $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    }
                }
            } catch {
                Write-IntuneToolkitLog "Error processing baseline folder $($folder.Name): $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        }
        if ($mergedBaselineSettings.Count -eq 0) {
            Write-IntuneToolkitLog "No baseline settings found in selected baselines." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            [System.Windows.MessageBox]::Show("No baseline settings found.", "Error")
            return
        }

        # ---------------------------------------------------------------------------
        # Load or fetch the human-readable settings catalog.
        # ---------------------------------------------------------------------------
        try {
            $catalogPath = ".\SupportFiles\SettingsCatalog.json"
            if (Test-Path $catalogPath) {
                Write-IntuneToolkitLog "Loading settings catalog from $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                $catalogContent = Get-Content $catalogPath -Raw
                $Catalog = $catalogContent | ConvertFrom-Json
            } else {
                Write-IntuneToolkitLog "Settings catalog file not found at $catalogPath. Fetching via Graph API." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
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
                Write-IntuneToolkitLog "Settings catalog fetched and saved to $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        } catch {
            Write-IntuneToolkitLog "Error loading or fetching settings catalog: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            return
        }

        # ---------------------------------------------------------------------------
        # Compare merged baseline settings against policy settings.
        # ---------------------------------------------------------------------------
        $totalBaselineSettings = $mergedBaselineSettings.Count
        $missingSettings = 0
        $matchesCount   = 0
        $differsCount   = 0
        try {
            foreach ($baselineEntry in $mergedBaselineSettings) {
                try {
                    $baselineSetting = $baselineEntry.Setting
                    $baselineId = $baselineSetting.settingInstance.settingDefinitionId
                    $expectedValue = $baselineSetting.settingInstance.choiceSettingValue.value
                    if ([string]::IsNullOrEmpty($expectedValue)) { $expectedValue = "Not Defined" }
                    $matches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $baselineId }
                    if (-not $matches -or $matches.Count -eq 0) {
                        $missingSettings++
                    } else {
                        $allMatch = $true
                        foreach ($match in $matches) {
                            if ($match.Setting.settingInstance.choiceSettingValue.value -ne $expectedValue) {
                                $allMatch = $false
                                break
                            }
                        }
                        if ($allMatch) { $matchesCount++ } else { $differsCount++ }
                    }
                } catch {
                    Write-IntuneToolkitLog "Error comparing baseline setting (ID: $($baselineSetting.settingInstance.settingDefinitionId)): $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                }
            }
        } catch {
            Write-IntuneToolkitLog "Error during baseline settings comparison: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
        try {
            $mergedIds = $mergedSettings | ForEach-Object { $_.Setting.settingInstance.settingDefinitionId } | Sort-Object -Unique
            $baselineIds = $mergedBaselineSettings | ForEach-Object { $_.Setting.settingInstance.settingDefinitionId } | Sort-Object -Unique
            $extraIds = $mergedIds | Where-Object { $_ -notin $baselineIds }
            $extraSettingsCount = $extraIds.Count
        } catch {
            Write-IntuneToolkitLog "Error determining extra settings: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }

        # ---------------------------------------------------------------------------
        # Generate Markdown report.
        # ---------------------------------------------------------------------------
        $reportLines = @()
        try {
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
            $reportLines += "| Baseline Policy | Description | Expected Value | Configured Policies | Actual Values | Comparison Result |"
            $reportLines += "|-----------------|-------------|----------------|---------------------|---------------|-------------------|"
            foreach ($baselineEntry in $mergedBaselineSettings) {
                try {
                    $baselinePolicy = $baselineEntry.BaselinePolicy
                    $baselineSetting = $baselineEntry.Setting
                    $baselineId = $baselineSetting.settingInstance.settingDefinitionId
                    $expectedValue = $baselineSetting.settingInstance.choiceSettingValue.value
                    if ([string]::IsNullOrEmpty($expectedValue)) { $expectedValue = "Not Defined" }
                    $readableExpected = if ($Catalog.Count -gt 0) { Get-SettingDisplayValue -settingValueId $expectedValue -Catalog $Catalog } else { $expectedValue }
                    $description = if ($Catalog.Count -gt 0) { Get-SettingDescription -settingId $baselineId -Catalog $Catalog } else { $baselineId }
                    $matches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $baselineId }
                    if (-not $matches -or $matches.Count -eq 0) {
                        $reportLines += "| $baselinePolicy | $description | $readableExpected | **Missing** | N/A | Missing |"
                    } else {
                        $policyList = ($matches | ForEach-Object { "$($_.PolicyName)" }) -join "; "
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
                        $reportLines += "| $baselinePolicy | $description | $readableExpected | $policyList | $actualValues | $comparison |"
                    }
                } catch {
                    Write-IntuneToolkitLog "Error generating report line for baseline setting: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                }
            }
            if ($extraIds.Count -gt 0) {
                $reportLines += ""
                $reportLines += "## Extra Settings (Not Defined in Baseline)"
                $reportLines += ""
                $reportLines += "| Description | Configured Policies | Actual Values |"
                $reportLines += "|-------------|---------------------|---------------|"
                foreach ($extra in $extraIds) {
                    try {
                        $extraMatches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $extra }
                        $policyList = ($extraMatches | ForEach-Object { "$($_.PolicyName)" }) -join "; "
                        $actualValuesRaw = ($extraMatches | ForEach-Object { $_.Setting.settingInstance.choiceSettingValue.value }) -join "; "
                        $actualValues = if ($Catalog.Count -gt 0) { ($extraMatches | ForEach-Object { Get-SettingDisplayValue -settingValueId $_.Setting.settingInstance.choiceSettingValue.value -Catalog $Catalog }) -join "; " } else { $actualValuesRaw }
                        $description = if ($Catalog.Count -gt 0) { Get-SettingDescription -settingId $extra -Catalog $Catalog } else { $extra }
                        $reportLines += "| $description | $policyList | $actualValues |"
                    } catch {
                        Write-IntuneToolkitLog "Error generating report line for extra setting: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    }
                }
            }
        } catch {
            Write-IntuneToolkitLog "Error generating Markdown report: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
        try {
            $reportContent = $reportLines -join "`r`n"
        } catch {
            Write-IntuneToolkitLog "Error joining report lines: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
        # ---------------------------------------------------------------------------
        # Save the Markdown report via a Save File Dialog.
        # ---------------------------------------------------------------------------
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $SaveDialog.Filter = "Markdown files (*.md)|*.md|All files (*.*)|*.*"
            $SaveDialog.Title = "Save Security Baseline Report As"
            if ($SaveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $SaveDialog.FileName -ne "") {
                $reportContent | Out-File -FilePath $SaveDialog.FileName -Encoding UTF8
                Write-IntuneToolkitLog "Security baseline report exported to $($SaveDialog.FileName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                [System.Windows.MessageBox]::Show("Security baseline report exported to $($SaveDialog.FileName)", "Success")
            } else {
                Write-IntuneToolkitLog "User canceled report export." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                [System.Windows.MessageBox]::Show("Report export canceled.", "Information")
            }
        } catch {
            Write-IntuneToolkitLog "Error saving report: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
    }
    catch {
        $errorMessage = "Failed to perform baseline analysis. Error: $($_.Exception.Message)"
        Write-IntuneToolkitLog $errorMessage -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
    }
})
