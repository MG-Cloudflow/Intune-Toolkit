<#
.SYNOPSIS
Performs a comprehensive security baseline analysis for configuration policies. This script retrieves configuration settings from Microsoft Graph, merges them with baseline expectations from JSON files, flattens group‐based settings into individual entries, compares the expected baseline values against the actual policy values, and produces a detailed Markdown report.

.DESCRIPTION
This script is invoked when the associated UI button is clicked and executes the following sequence:
  - Validates that at least one configuration policy is selected by the user.
  - Retrieves detailed configuration policy settings via the Microsoft Graph API.
  - Merges settings from all selected policies into a single collection.
  - Scans a specified baseline root folder (".\SupportFiles\Intune Baselines") for available baseline folders.
  - If multiple baseline folders are found, displays a dialog for the user to select one or more baselines.
  - For each selected baseline folder, reads JSON files (found in the "SettingsCatalog" subfolder) containing baseline settings.
       - If multiple JSON files exist, the user is prompted to select the desired baseline policies.
  - Merges baseline settings from the chosen JSON files.
  - FLATTENING:
       * Both baseline and policy settings are “flattened” such that group‐based settings are separated:
         – For a group container, each child setting is processed individually.
         – A composite description is built in the format: ParentSettingDefinitionID\ChildSettingDefinitionID.
         – Non‐group settings are output directly.
  - COMPARISON:
       * The flattened baseline settings (expected values) are compared against the flattened policy settings (actual values).
       * A summary is generated indicating Matches, Differences, Missing baseline settings, and Extra policy settings.
  - The final Markdown report includes a detailed table with the following columns:
       - Baseline Policy
       - Display Name (Parent\Child) – friendly names obtained from the catalog
       - Description (from the catalog)
       - Expected Value (friendly lookup)
       - Configured Policies
       - Actual Values (friendly lookup)
       - Comparison Result
  - If a friendly catalog entry is not found (or if the raw value is too long), a safety message is displayed.
  - Extra policy settings (found in the policy but not defined in the baseline) are also processed using the friendly lookup logic.
  - Finally, the report is saved using a Save File dialog.

.NOTES
Author: Maxime Guillemin
Date: 07/03/2025

.EXAMPLE
$SecurityBaselineAnalysisButton.Add_Click({
    # Executes the baseline analysis (raw compare version with display info)
})
#>
#region Main Script

#--------------------------------------------------------------------------------
# Main Script: Event Handler for Security Baseline Analysis Button
# This block is executed when the user clicks the Security Baseline Analysis button.
# It validates policy selection, fetches and merges policy settings via Graph API,
# processes baseline folders and JSON files, flattens settings, compares baseline against policy,
# and generates a Markdown report.
#--------------------------------------------------------------------------------
$SecurityBaselineAnalysisButton.Add_Click({
    try {
        Write-IntuneToolkitLog "SecurityBaselineAnalysisButton clicked" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        #--------------------------------------------------------------------------------
        # Block: Validate Selected Policies
        # Ensure that at least one configuration policy is selected in the UI.
        #--------------------------------------------------------------------------------
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

        #--------------------------------------------------------------------------------
        # Block: Fetch and Merge Policy Settings via Graph API
        # Retrieve detailed configuration policy settings for each selected policy and merge them.
        #--------------------------------------------------------------------------------
        $mergedSettings = @()
        foreach ($policy in $PolicyDataGrid.SelectedItems) {
            try {
                # Determine the policy ID (it could be stored as PolicyId or id).
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
                # Merge settings from the policy if available.
                if ($policyDetail -and $policyDetail.settings) {
                    # Ensure the settings are treated as an array.
                    $settingsArray = if (-not ($policyDetail.settings -is [System.Array])) { @($policyDetail.settings) } else { $policyDetail.settings }
                    if ($settingsArray.Count -gt 0) {
                        Write-IntuneToolkitLog "Merging settings from policy: $($policyDetail.name) ($policyId); Settings count: $($settingsArray.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        foreach ($setting in $settingsArray) {
                            $mergedSettings += [PSCustomObject]@{
                                PolicyId   = $policyDetail.id
                                PolicyName = $policyDetail.name
                                Setting    = $setting
                            }
                        }
                    } else {
                        Write-IntuneToolkitLog "Policy $policyId returned an empty settings array." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    }
                } else {
                    Write-IntuneToolkitLog "Policy $policyId has no settings to merge." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                }
            } catch {
                Write-IntuneToolkitLog "Error processing policy $($policy.id): $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        }
        Write-IntuneToolkitLog "Total merged policy settings count: $($mergedSettings.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        Write-IntuneToolkitLog ("Raw Merged Policy Settings: " + ($mergedSettings | ConvertTo-Json -Depth 10)) -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        #--------------------------------------------------------------------------------
        # Block: Flatten Policy Settings
        # Process and flatten the merged policy settings for easier comparison.
        #--------------------------------------------------------------------------------
        $flattenedPolicy = Flatten-PolicySettings -MergedPolicy $mergedSettings
        Write-IntuneToolkitLog ("Flattened Policy Settings (raw): " + ($flattenedPolicy | ConvertTo-Json -Depth 10)) -component "PolicyFlatten" -file "SecurityBaselineAnalysisButton.ps1"

        #--------------------------------------------------------------------------------
        # Block: Locate and Validate Baseline Folders
        # Check that the baseline root folder exists and retrieve the available baseline folders.
        #--------------------------------------------------------------------------------
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

        #--------------------------------------------------------------------------------
        # Block: Baseline Folder and Policy Selection
        # If multiple baseline folders exist, prompt the user to select one or more.
        #--------------------------------------------------------------------------------
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

        #--------------------------------------------------------------------------------
        # Block: Process Baseline Folders and Load JSON Baseline Policies
        # For each selected baseline folder, load and merge JSON baseline policies.
        #--------------------------------------------------------------------------------
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

                # If more than one JSON file exists, prompt the user to select which baseline policies to use.
                if ($catalogFiles.Count -gt 1) {
                    $policyNames = @()
                    foreach ($file in $catalogFiles) {
                        try {
                            $jsonContent = Get-Content $file.FullName -Raw | ConvertFrom-Json
                            $policyName = $jsonContent.name
                            if (-not $policyName) { 
                                $policyName = $file.BaseName
                                Write-IntuneToolkitLog "No 'name' property in $($file.FullName); using file name '$policyName'" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                            } else {
                                Write-IntuneToolkitLog "Found baseline policy '$policyName' in file $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                            }
                            $policyNames += $policyName
                        } catch {
                            Write-IntuneToolkitLog "Error extracting baseline policy name from file $($file.FullName): $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        }
                    }
                    $selectedPolicyNames = Show-BaselineSelectionDialog -Items $policyNames -Title "Select Baseline Policies from $($folder.Name)" -Height 500 -Width 600
                    if (-not $selectedPolicyNames) {
                        Write-IntuneToolkitLog "User did not select any baseline policies for folder: $($folder.Name)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        continue
                    }
                    $catalogFiles = $catalogFiles | Where-Object {
                        try {
                            $jsonContent = Get-Content $_.FullName -Raw | ConvertFrom-Json
                            $filePolicyName = $jsonContent.name
                            if (-not $filePolicyName) { $filePolicyName = $_.BaseName }
                            return $selectedPolicyNames -contains $filePolicyName
                        } catch {
                            return $false
                        }
                    }
                }

                # Process each JSON file and merge its baseline settings.
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
                        $baselinePolicyName = $jsonContent.name
                        if (-not $baselinePolicyName) {
                            Write-IntuneToolkitLog "No 'name' property found in $($file.FullName); using folder name $($folder.Name) as baseline policy name" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                            $baselinePolicyName = $folder.Name
                        } else {
                            Write-IntuneToolkitLog "Extracted baseline policy name '$baselinePolicyName' from $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        }
                        foreach ($setting in $jsonContent.settings) {
                            $mergedBaselineSettings += [PSCustomObject]@{
                                BaselinePolicy = $baselinePolicyName
                                Setting        = $setting
                            }
                        }
                        Write-IntuneToolkitLog "Merged baseline settings from file: $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
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
        Write-IntuneToolkitLog ("Raw Baseline JSON Merged: " + ($mergedBaselineSettings | ConvertTo-Json -Depth 10)) -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        #--------------------------------------------------------------------------------
        # Block: Flatten Baseline Settings
        # Flatten the merged baseline settings for easier comparison with policy settings.
        #--------------------------------------------------------------------------------
        $flattenedBaseline = Flatten-BaselineSettings -MergedBaseline $mergedBaselineSettings
        Write-IntuneToolkitLog ("Flattened Baseline Settings (raw): " + ($flattenedBaseline | ConvertTo-Json -Depth 10)) -component "BaselineFlatten" -file "SecurityBaselineAnalysisButton.ps1"

        #--------------------------------------------------------------------------------
        # Block: Load and Cache Settings Catalog
        # Load a human-readable settings catalog from a local file or fetch via Graph API if not found.
        #--------------------------------------------------------------------------------
        try {
            $catalogPath = ".\SupportFiles\SettingsCatalog.json"
            if (Test-Path $catalogPath) {
                Write-IntuneToolkitLog "Loading settings catalog from $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                $rawCatalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json
                $CatalogDictionary = Build-CatalogDictionary -Catalog $rawCatalog
            } else {
                Write-IntuneToolkitLog "Settings catalog file not found at $catalogPath. Fetching via Graph API." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                #$settingsurl = "https://graph.microsoft.com/beta/deviceManagement/configurationCategories?&$filter=(platforms%20has%20'windows10')%20and%20(technologies%20has%20'mdm')"
                $settingsurl = "https://graph.microsoft.com/beta/deviceManagement/configurationCategories"
                $Settingscatalog = Get-GraphData -url $settingsurl
                $Catalog = @()
                $Catalog += $Settingscatalog | ForEach-Object {
                    $categoryId = [System.Web.HttpUtility]::UrlEncode($_.id)
                    #$settingchilditemurl = "https://graph.microsoft.com/beta/deviceManagement/configurationSettings?`$filter=categoryId eq '$categoryId' and visibility has 'settingsCatalog' and (applicability/platform has 'windows10') and (applicability/technologies has 'mdm')"
                    $settingchilditemurl = "https://graph.microsoft.com/beta/deviceManagement/configurationSettings?`$filter=categoryId eq '$categoryId'"
                    Get-GraphData -url $settingchilditemurl
                }
                # Convert the catalog to JSON and save it locally for future use.
                $CatalogJson = $Catalog | ConvertTo-Json -Depth 10
                $catalogDir = Split-Path $catalogPath
                if (-not (Test-Path $catalogDir)) {
                    New-Item -Path $catalogDir -ItemType Directory -Force | Out-Null
                }
                $CatalogJson | Out-File -FilePath $catalogPath -Encoding UTF8
                $CatalogDictionary = Build-CatalogDictionary -Catalog $Catalog
                Write-IntuneToolkitLog "Settings catalog fetched and saved to $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        } catch {
            Write-IntuneToolkitLog "Error loading or fetching settings catalog: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            return
        }

        #--------------------------------------------------------------------------------
        # Block: Compare Baseline and Policy Settings
        # Compare the flattened baseline settings (expected) against the flattened policy settings (actual)
        # and build the comparison report.
        #--------------------------------------------------------------------------------
        $totalBaselineSettings = $flattenedBaseline.Count
        $missingSettings = 0
        $matchesCount = 0
        $differsCount = 0
        $comparisonReport = @()
        
        foreach ($item in $flattenedBaseline) {
            $bp = $item.BaselinePolicy
            $baselineId = $item.BaselineId
            $expectedValue = $item.ExpectedValue

            # Build display composite:
            if ($item.CompositeDescription -match "\\") {
                $displayComposite = Convert-CompositeToDisplay -RawComposite $item.CompositeDescription -CatalogDictionary $CatalogDictionary
            } else {
                $displayComposite = Get-SettingDisplayValue -settingValueId $baselineId -CatalogDictionary $CatalogDictionary
            }
            $displayDescription = Get-SettingDescription -settingId $baselineId -CatalogDictionary $CatalogDictionary
            # Remove newlines from description for clean display.
            $displayDescription = ($displayDescription -replace "[\r\n]+", " ").Trim()
            # Look up the friendly expected value.
            $expectedDisplay = Get-SettingDisplayValue -settingValueId $expectedValue -CatalogDictionary $CatalogDictionary

            # Use the Maybe-Shorten function to check for overly long or raw values.
            $displayComposite = Maybe-Shorten -raw $item.CompositeDescription -friendly $displayComposite
            $displayDescription = Maybe-Shorten -raw $baselineId -friendly $displayDescription
            $expectedDisplay = Maybe-Shorten -raw $expectedValue -friendly $expectedDisplay

            Write-IntuneToolkitLog ("Catalog lookup for '$baselineId': Display='$displayComposite', Description='$displayDescription'") -component "CatalogLookup" -file "SecurityBaselineAnalysisButton.ps1"
            Write-IntuneToolkitLog ("Comparing baseline item: Policy='$bp', BaselineId='$baselineId', ExpectedValue='$expectedValue'") -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"

            # Find matching policy settings based on the baseline setting ID.
            $policyMatches = $flattenedPolicy | Where-Object { $_.PolicySettingId -eq $baselineId }
            if (-not $policyMatches -or $policyMatches.Count -eq 0) {
                # If no match is found, add a report line indicating a missing policy.
                $comparisonReport += "| $bp | $displayComposite | $displayDescription | $expectedDisplay | **Missing** | N/A | Missing |"
                $missingSettings++
                Write-IntuneToolkitLog ("No matching policy settings found for BaselineId '$baselineId'") -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
            } else {
                # Concatenate the names of the policies that have a matching setting.
                $policyList = ($policyMatches | ForEach-Object { "$($_.PolicyName)" }) -join "; "
                # Look up the friendly display value for the actual values.
                $actualValuesDisplay = ($policyMatches | ForEach-Object { Get-SettingDisplayValue -settingValueId $_.ActualValue -CatalogDictionary $CatalogDictionary }) -join "; "
                $actualValuesDisplay = Maybe-Shorten -raw ($policyMatches | ForEach-Object { $_.ActualValue } | Out-String) -friendly $actualValuesDisplay
                $allMatch = $true
                # Check if every matched policy setting has the expected value.
                foreach ($match in $policyMatches) {
                    if ($match.ActualValue -ne $expectedValue) {
                        $allMatch = $false
                        break
                    }
                }
                $comparison = if ($allMatch) { "Matches" } else { "Differs" }
                $comparisonReport += "| $bp | $displayComposite | $displayDescription | $expectedDisplay | $policyList | $actualValuesDisplay | $comparison |"
                Write-IntuneToolkitLog ("Comparison for BaselineId '$baselineId': Expected='$expectedDisplay', PolicyList='$policyList', Actual='$actualValuesDisplay', Comparison='$comparison'") -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                if ($allMatch) { $matchesCount++ } else { $differsCount++ }
            }
        }

        #--------------------------------------------------------------------------------
        # Block: Determine Extra Policy Settings
        # Identify policy settings that exist in the policy but are not defined in the baseline.
        #--------------------------------------------------------------------------------
        try {
            $policyIds = $flattenedPolicy | ForEach-Object { $_.PolicySettingId } | Sort-Object -Unique
            $baselineIds = $flattenedBaseline | ForEach-Object { $_.BaselineId } | Sort-Object -Unique
            $extraIds = $policyIds | Where-Object { $_ -notin $baselineIds }
            $extraSettingsCount = $extraIds.Count
            Write-IntuneToolkitLog ("Extra Setting IDs: " + ($extraIds -join ", ")) -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
        } catch {
            Write-IntuneToolkitLog "Error determining extra settings: $($_.Exception.Message)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
        }

        #--------------------------------------------------------------------------------
        # Block: Generate Markdown Report
        # Build the Markdown report containing the summary and detailed comparison of baseline and policy settings.
        #--------------------------------------------------------------------------------
        try {
            $reportLines = @()
            $reportLines += "# $($folder.Name) Analysis Report "
            $reportLines += ""
            $reportLines += "## Summary"
            $reportLines += ""
            $reportLines += "- Total baseline settings: $totalBaselineSettings"
            $reportLines += "- Configured settings (Matches): $matchesCount"
            $reportLines += "- Configured settings (Differ): $differsCount"
            $reportLines += "- Missing baseline settings: $missingSettings"
            $reportLines += "- Extra settings: $extraSettingsCount"
            $reportLines += ""
            $reportLines += "## Baseline Settings Comparison (Raw)"
            $reportLines += ""
            $reportLines += "| Baseline Policy | Display Name (Parent\Child) | Description | Expected Value | Configured Policies | Actual Values | Comparison Result |"
            $reportLines += "|-----------------|-----------------------------|-------------|----------------|---------------------|---------------|-------------------|"
            $reportLines += $comparisonReport

            # If there are extra policy settings not defined in the baseline, add an extra section to the report.
            if ($extraSettingsCount -gt 0) {
                $reportLines += ""
                $reportLines += "## Extra Policy Settings (Not Defined in Baseline)"
                $reportLines += ""
                $reportLines += "| Policy Name | Display Name (Parent\Child) | Description | Actual Value |"
                $reportLines += "|-------------|-----------------------------|-------------|--------------|"
                foreach ($extraId in $extraIds) {
                    $exMatches = $flattenedPolicy | Where-Object { $_.PolicySettingId -eq $extraId }
                    $pnames = ($exMatches | ForEach-Object { "$($_.PolicyName)" }) -join "; "
                    if ($extraId -match "\\") {
                        $displayComposite = Convert-CompositeToDisplay -RawComposite $extraId -CatalogDictionary $CatalogDictionary
                    } else {
                        $displayComposite = Get-SettingDisplayValue -settingValueId $extraId -CatalogDictionary $CatalogDictionary
                    }
                    $displayDescription = Get-SettingDescription -settingId $extraId -CatalogDictionary $CatalogDictionary
                    $displayComposite = Maybe-Shorten -raw $extraId -friendly $displayComposite
                    $displayDescription = Maybe-Shorten -raw $extraId -friendly $displayDescription
                    $aval = ($exMatches | ForEach-Object { Get-SettingDisplayValue -settingValueId $_.ActualValue -CatalogDictionary $CatalogDictionary }) -join "; "
                    $aval = Maybe-Shorten -raw ($exMatches | ForEach-Object { $_.ActualValue } | Out-String) -friendly $aval

                    $reportLines += "| $pnames | $displayComposite | $displayDescription | $aval |"
                }
            }
        } catch {
            Write-IntuneToolkitLog "Error generating Markdown report: $($_.Exception.Message)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
        }
        try {
            # Join all report lines into a single string with proper line breaks.
            $reportContent = $reportLines -join "`r`n"
        } catch {
            Write-IntuneToolkitLog "Error joining report lines: $($_.Exception.Message)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
        }

        #--------------------------------------------------------------------------------
        # Block: Save Report Using Save File Dialog (with separate CSVs)
        # Prompt the user to save the generated Markdown report and two CSVs.
        #--------------------------------------------------------------------------------
        try {
            # --- Add filename template logic ---
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $baseName  = "$($folder.Name)_AnalysisReport_$timestamp"
            # ------------------------------------

            # 1) Build two CSV tables: baseline comparison and extra policy settings
            $baselineComparisonObjects = @()
            foreach ($item in $flattenedBaseline) {
                $bp               = $item.BaselinePolicy
                $baselineId       = $item.BaselineId
                $expectedValue    = $item.ExpectedValue

                # Friendly lookups
                if ($item.CompositeDescription -match "\\") {
                    $displayName = Convert-CompositeToDisplay -RawComposite $item.CompositeDescription -CatalogDictionary $CatalogDictionary
                } else {
                    $displayName = Get-SettingDisplayValue -settingValueId $baselineId -CatalogDictionary $CatalogDictionary
                }
                $description = Get-SettingDescription -settingId $baselineId -CatalogDictionary $CatalogDictionary
                $expected    = Get-SettingDisplayValue -settingValueId $expectedValue -CatalogDictionary $CatalogDictionary

                # Find policy matches
                $matches = $flattenedPolicy | Where-Object { $_.PolicySettingId -eq $baselineId }
                if (-not $matches) {
                    $status = 'Missing'
                    $policies = ''
                    $actual   = ''
                } else {
                    $policies = ($matches | ForEach-Object { $_.PolicyName }) -join '; '
                    $actual   = ($matches | ForEach-Object {
                        Get-SettingDisplayValue -settingValueId $_.ActualValue -CatalogDictionary $CatalogDictionary
                    }) -join '; '
                    $allMatch = $matches | ForEach-Object { $_.ActualValue } | Where-Object { $_ -ne $expectedValue } | Measure-Object | Select-Object -ExpandProperty Count
                    $status   = if ($allMatch -eq 0) { 'Matches' } else { 'Differs' }
                }

                $baselineComparisonObjects += [PSCustomObject]@{
                    BaselinePolicy     = $bp
                    DisplayName        = $displayName
                    Description        = $description
                    ExpectedValue      = $expected
                    ConfiguredPolicies = $policies
                    ActualValues       = $actual
                    Comparison         = $status
                }
            }

            $extraSettingsObjects = @()
            $baselineIds = $flattenedBaseline | ForEach-Object { $_.BaselineId } | Sort-Object -Unique
            $allPolicyIds = $flattenedPolicy | ForEach-Object { $_.PolicySettingId } | Sort-Object -Unique
            $extraIds = $allPolicyIds | Where-Object { $_ -notin $baselineIds }
            foreach ($extraId in $extraIds) {
                $matches = $flattenedPolicy | Where-Object { $_.PolicySettingId -eq $extraId }
                $policies = ($matches | ForEach-Object { $_.PolicyName }) -join '; '
                if ($extraId -match "\\") {
                    $displayName = Convert-CompositeToDisplay -RawComposite $extraId -CatalogDictionary $CatalogDictionary
                } else {
                    $displayName = Get-SettingDisplayValue -settingValueId $extraId -CatalogDictionary $CatalogDictionary
                }
                $description = Get-SettingDescription -settingId $extraId -CatalogDictionary $CatalogDictionary
                $actual      = ($matches | ForEach-Object {
                    Get-SettingDisplayValue -settingValueId $_.ActualValue -CatalogDictionary $CatalogDictionary
                }) -join '; '

                $extraSettingsObjects += [PSCustomObject]@{
                    PolicyName   = $policies
                    DisplayName  = $displayName
                    Description  = $description
                    ActualValue  = $actual
                }
            }

            # 2) Ask the user which formats to export
            $formats = Show-ExportOptionsDialog
            if (-not $formats -or $formats.Count -eq 0) {
                Write-IntuneToolkitLog "User canceled export options." -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                [System.Windows.MessageBox]::Show("Export canceled by user.","Information")
                return
            }

            Add-Type -AssemblyName System.Windows.Forms

            # 3) For each selected format, show SaveFileDialog(s) and write out
            foreach ($fmt in $formats) {
                switch ($fmt) {
                    "Markdown" {
                        $dlgMd = New-Object System.Windows.Forms.SaveFileDialog
                        $dlgMd.Filter   = "Markdown files (*.md)|*.md|All files (*.*)|*.*"
                        $dlgMd.Title    = "Save Security Baseline Report as Markdown"
                        $dlgMd.FileName = "$baseName.md"

                        if ($dlgMd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlgMd.FileName) {
                            $reportContent | Out-File -FilePath $dlgMd.FileName -Encoding UTF8
                            Write-IntuneToolkitLog "Exported Markdown report to $($dlgMd.FileName)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                        } else {
                            Write-IntuneToolkitLog "User canceled Markdown export." -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                        }
                    }
                    "CSV" {
                        # a) Baseline comparison CSV
                        $dlg1 = New-Object System.Windows.Forms.SaveFileDialog
                        $dlg1.Filter   = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
                        $dlg1.Title    = "Save Baseline Comparison as CSV"
                        $dlg1.FileName = "$baseName`_BaselineComparison.csv"

                        if ($dlg1.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlg1.FileName) {
                            $baselineComparisonObjects | Export-Csv -Path $dlg1.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
                            Write-IntuneToolkitLog "Exported baseline CSV to $($dlg1.FileName)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                        } else {
                            Write-IntuneToolkitLog "User canceled baseline CSV export." -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                        }

                        # b) Extra policy settings CSV (if any)
                        if ($extraSettingsObjects.Count -gt 0) {
                            $dlg2 = New-Object System.Windows.Forms.SaveFileDialog
                            $dlg2.Filter   = $dlg1.Filter
                            $dlg2.Title    = "Save Extra Policy Settings as CSV"
                            $dlg2.FileName = "$baseName`_ExtraSettings.csv"

                            if ($dlg2.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlg2.FileName) {
                                $extraSettingsObjects | Export-Csv -Path $dlg2.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
                                Write-IntuneToolkitLog "Exported extra settings CSV to $($dlg2.FileName)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                            } else {
                                Write-IntuneToolkitLog "User canceled extra CSV export." -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                            }
                        }
                    }
                }
            }

            [System.Windows.MessageBox]::Show("Report export complete.","Success")
        }
        catch {
            Write-IntuneToolkitLog "Error exporting reports: $($_.Exception.Message)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
            [System.Windows.MessageBox]::Show("Error exporting reports: $($_.Exception.Message)", "Error")
        }
    }
    catch {
        #--------------------------------------------------------------------------------
        # Block: Error Handling
        # Log and display an error message if the baseline analysis fails.
        #--------------------------------------------------------------------------------
        $errorMessage = "Failed to perform baseline analysis. Error: $($_.Exception.Message)"
        Write-IntuneToolkitLog $errorMessage -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
    }
})
#endregion Main Script
