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
        #Write-IntuneToolkitLog ("Raw Merged Policy Settings: " + ($mergedSettings | ConvertTo-Json -Depth 20)) -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        #--------------------------------------------------------------------------------
        # Block: Flatten Policy Settings
        # Process and flatten the merged policy settings for easier comparison.
        #--------------------------------------------------------------------------------
        $flattenedPolicy = Flatten-PolicySettings -MergedPolicy $mergedSettings
        #Write-IntuneToolkitLog ("Flattened Policy Settings (raw): " + ($flattenedPolicy | ConvertTo-Json -Depth 30)) -component "PolicyFlatten" -file "SecurityBaselineAnalysisButton.ps1"

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
        #Write-IntuneToolkitLog ("Raw Baseline JSON Merged: " + ($mergedBaselineSettings | ConvertTo-Json -Depth 10)) -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        #--------------------------------------------------------------------------------
        # Block: Flatten Baseline Settings
        # Flatten the merged baseline settings for easier comparison with policy settings.
        #--------------------------------------------------------------------------------
        $flattenedBaseline = Flatten-BaselineSettings -MergedBaseline $mergedBaselineSettings
        #Write-IntuneToolkitLog ("Flattened Baseline Settings (raw): " + ($flattenedBaseline | ConvertTo-Json -Depth 10)) -component "BaselineFlatten" -file "SecurityBaselineAnalysisButton.ps1"

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

            #Write-IntuneToolkitLog ("Catalog lookup for '$baselineId': Display='$displayComposite', Description='$displayDescription'") -component "CatalogLookup" -file "SecurityBaselineAnalysisButton.ps1"
            #Write-IntuneToolkitLog ("Comparing baseline item: Policy='$bp', BaselineId='$baselineId', ExpectedValue='$expectedValue'") -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"

            # Find matching policy settings based on the baseline setting ID.
            $policyMatches = $flattenedPolicy | Where-Object { $_.PolicySettingId -eq $baselineId }
            if (-not $policyMatches -or $policyMatches.Count -eq 0) {
                # If no match is found, add a report line indicating a missing policy.
                $comparisonReport += "| $bp | $displayComposite | $displayDescription | $expectedDisplay | **Missing** | N/A | Missing |"
                $missingSettings++
                #Write-IntuneToolkitLog ("No matching policy settings found for BaselineId '$baselineId'") -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
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
                #Write-IntuneToolkitLog ("Comparison for BaselineId '$baselineId': Expected='$expectedDisplay', PolicyList='$policyList', Actual='$actualValuesDisplay', Comparison='$comparison'") -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
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

                     # Metadata (Platform/Technologies/Keywords) from catalog wrapper
                     $catalogEntry = Find-CatalogEntry -CatalogDictionary $CatalogDictionary -Key $baselineId
                     $platformMeta = if($catalogEntry -and $catalogEntry.Platform){ $catalogEntry.Platform } else { '' }
                     if($platformMeta -and $platformMeta -match '^(?i)windows10$'){ $platformMeta = 'Windows' }
                     $techMeta     = if($catalogEntry -and $catalogEntry.Technologies){
                                                if($catalogEntry.Technologies -is [System.Array]){ ($catalogEntry.Technologies -join ', ') } else { [string]$catalogEntry.Technologies }
                                            } else { '' }
                     $keywordsMeta = if($catalogEntry -and $catalogEntry.Keywords){ $catalogEntry.Keywords } else { '' }

                # Find policy matches (avoid using automatic variable $Matches)
                $policyMatches = $flattenedPolicy | Where-Object { $_.PolicySettingId -eq $baselineId }
                if (-not $policyMatches) {
                    $status = 'Missing'
                    $policies = ''
                    $actual   = ''
                } else {
                    # Deduplicate by PolicyId + ActualValue to avoid duplicate value repeats within same policy
                    $uniqueMatches = $policyMatches |
                        Sort-Object -Property PolicyId, ActualValue -Unique
                    # Make configured policy list unique & sorted (based on unique matches)
                    $policies = ($uniqueMatches | ForEach-Object { $_.PolicyName } | Sort-Object -Unique) -join '; '
                    $actual   = ($uniqueMatches | ForEach-Object {
                        Get-SettingDisplayValue -settingValueId $_.ActualValue -CatalogDictionary $CatalogDictionary
                    }) -join '; '
                    $allMatch = $uniqueMatches | ForEach-Object { $_.ActualValue } | Where-Object { $_ -ne $expectedValue } | Measure-Object | Select-Object -ExpandProperty Count
                    $status   = if ($allMatch -eq 0) { 'Matches' } else { 'Differs' }
                }

                $baselineComparisonObjects += [PSCustomObject]@{
                    BaselinePolicy     = $bp
                    DisplayName        = $displayName
                    Platform           = $platformMeta
                    Technologies       = $techMeta
                    Keywords           = $keywordsMeta
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
                $extraMatches = $flattenedPolicy | Where-Object { $_.PolicySettingId -eq $extraId }
                # Deduplicate by PolicyId + ActualValue
                $uniqueExtra = $extraMatches | Sort-Object -Property PolicyId, ActualValue -Unique
                # Unique & sorted list of policy names for extra settings
                $policies = ($uniqueExtra | ForEach-Object { $_.PolicyName } | Sort-Object -Unique) -join '; '
                if ($extraId -match "\\") {
                    $displayName = Convert-CompositeToDisplay -RawComposite $extraId -CatalogDictionary $CatalogDictionary
                } else {
                    $displayName = Get-SettingDisplayValue -settingValueId $extraId -CatalogDictionary $CatalogDictionary
                }
                $description = Get-SettingDescription -settingId $extraId -CatalogDictionary $CatalogDictionary
                $actual      = ($uniqueExtra | ForEach-Object {
                    Get-SettingDisplayValue -settingValueId $_.ActualValue -CatalogDictionary $CatalogDictionary
                }) -join '; '

                # Metadata for extra settings
                $catalogEntry = Find-CatalogEntry -CatalogDictionary $CatalogDictionary -Key $extraId
                $platformMeta = if($catalogEntry -and $catalogEntry.Platform){ $catalogEntry.Platform } else { '' }
                if($platformMeta -and $platformMeta -match '^(?i)windows10$'){ $platformMeta = 'Windows' }
                $techMeta     = if($catalogEntry -and $catalogEntry.Technologies){
                                    if($catalogEntry.Technologies -is [System.Array]){ ($catalogEntry.Technologies -join ', ') } else { [string]$catalogEntry.Technologies }
                                 } else { '' }
                $keywordsMeta = if($catalogEntry -and $catalogEntry.Keywords){ $catalogEntry.Keywords } else { '' }

                $extraSettingsObjects += [PSCustomObject]@{
                    PolicyName   = $policies
                    DisplayName  = $displayName
                    Platform     = $platformMeta
                    Technologies = $techMeta
                    Keywords     = $keywordsMeta
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
                                        "HTML" {
                                                try {
                                                        $dlgHtml = New-Object System.Windows.Forms.SaveFileDialog
                                                        $dlgHtml.Filter   = "HTML files (*.html)|*.html|All files (*.*)|*.*"
                                                        $dlgHtml.Title    = "Save Security Baseline Report as HTML"
                                                        $dlgHtml.FileName = "$baseName.html"
                                                        if ($dlgHtml.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or -not $dlgHtml.FileName) { continue }

                                                        # Collect selected baseline folder names for summary
                                                        $baselineNameList = ($selectedBaselineFolders | ForEach-Object { $_.Name }) -join ', '

                                                        # Icon / logo
                                                        $iconBase64 = ''
                                                        $iconPathIco = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.ico'
                                                        if (Test-Path $iconPathIco) { $bytesIco = [System.IO.File]::ReadAllBytes($iconPathIco); $iconBase64 = [Convert]::ToBase64String($bytesIco) }
                                                        $headerLogoBase64 = ''
                                                        $headerLogoMime = 'image/png'
                                                        $logoPathPng = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.png'
                                                        if (Test-Path $logoPathPng) { $logoBytes = [System.IO.File]::ReadAllBytes($logoPathPng); $headerLogoBase64 = [Convert]::ToBase64String($logoBytes) } elseif ($iconBase64) { $headerLogoBase64 = $iconBase64; $headerLogoMime='image/x-icon' }
                                                        $iconImg = if ($headerLogoBase64) { "<img src='data:$headerLogoMime;base64,$headerLogoBase64' class='header-logo' alt='Intune Toolkit Logo'>" } else { '' }

                                                        $pct = { param($n,$d) if($d){ [math]::Round(($n/$d)*100,1) } else { 0 } }
                                                        $matchesPct = & $pct $matchesCount $totalBaselineSettings
                                                        $differsPct = & $pct $differsCount $totalBaselineSettings
                                                        $missingPct = & $pct $missingSettings $totalBaselineSettings
                                                        $extraPct   = & $pct $extraSettingsCount $totalBaselineSettings

                            # Build tag list (unique keywords across baseline & extra objects)
                            $allTags = @()
                            foreach($o in $baselineComparisonObjects){ if($o.Keywords){ $allTags += ($o.Keywords -split '\s*,\s*') } }
                            foreach($o in $extraSettingsObjects){ if($o.Keywords){ $allTags += ($o.Keywords -split '\s*,\s*') } }
                            $allTags = $allTags | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique
                            $tagOptionsHtml = ($allTags | ForEach-Object {
                                $tEsc = [System.Web.HttpUtility]::HtmlEncode($_)
                                $idSafe = ($tEsc -replace "[^a-zA-Z0-9_-]","_")
                                "<div class='form-check form-check-sm'><input class='form-check-input tag-filter-cb' type='checkbox' value='$tEsc' id='tag_$idSafe'><label class='form-check-label small' for='tag_$idSafe'>$tEsc</label></div>"
                            }) -join "`n"

                            # Platform distribution + filters
                            $platformCounts = @{}
                            foreach($o in $baselineComparisonObjects){ if($o.Platform){ $norm = ($o.Platform -replace '\s+',''); if($norm -match '^(?i)windows10$'){ $norm='Windows' }; if(-not $platformCounts.ContainsKey($norm)){ $platformCounts[$norm]=0 }; $platformCounts[$norm]++ } }
                            foreach($o in $extraSettingsObjects){ if($o.Platform){ $norm = ($o.Platform -replace '\s+',''); if($norm -match '^(?i)windows10$'){ $norm='Windows' }; if(-not $platformCounts.ContainsKey($norm)){ $platformCounts[$norm]=0 }; $platformCounts[$norm]++ } }
                            $platformFilterOptions = ($platformCounts.Keys | Sort-Object | ForEach-Object {
                                $p = $_; $count = $platformCounts[$_]; $pEsc = [System.Web.HttpUtility]::HtmlEncode($p)
                                $idSafe = ($pEsc -replace "[^a-zA-Z0-9_-]","_")
                                "<div class='form-check form-check-sm'><input class='form-check-input platform-filter-cb' type='checkbox' value='$pEsc' id='plat_$idSafe'><label class='form-check-label small' for='plat_$idSafe'>$pEsc <span class='text-muted'>($count)</span></label></div>"
                            }) -join "`n"

                            # Sort objects: Matches (0), Differs (1), Missing (2), others (3)
                            $baselineComparisonObjects = $baselineComparisonObjects | Sort-Object -Property @{ Expression = { switch ($_.Comparison) { 'Matches' {0} 'Differs' {1} 'Missing' {2} default {3} } } }, DisplayName
                            $comparisonRowsHtml = foreach ($o in $baselineComparisonObjects) {
                                                                $bpEsc   = [System.Web.HttpUtility]::HtmlEncode($o.BaselinePolicy)
                                                                $dnEsc   = [System.Web.HttpUtility]::HtmlEncode($o.DisplayName)
                                                                $platEsc = [System.Web.HttpUtility]::HtmlEncode($o.Platform)
                                                                $techEsc = [System.Web.HttpUtility]::HtmlEncode($o.Technologies)
                                                                # (keywords handled via tag badges)
                                                                $tagBadgesHtml = ''
                                                                $dataTags = ''
                                                                if($o.Keywords){
                                                                    $tags = $o.Keywords -split '\s*,\s*' | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique
                                                                    $dataTags = ($tags | ForEach-Object { $_.ToLower() }) -join ','
                                                                    $tagBadgesHtml = ($tags | ForEach-Object { $t = [System.Web.HttpUtility]::HtmlEncode($_); "<span class='badge me-1 tag-badge' data-tag='$t'>$t</span>" }) -join ''
                                                                }
                                                                $descEsc = [System.Web.HttpUtility]::HtmlEncode(($o.Description -replace "`r?`n", ' '))
                                                                $expEsc  = [System.Web.HttpUtility]::HtmlEncode($o.ExpectedValue)
                                                                $polEsc  = [System.Web.HttpUtility]::HtmlEncode($o.ConfiguredPolicies)
                                                                $actEsc  = [System.Web.HttpUtility]::HtmlEncode($o.ActualValues)
                                                                $cmp     = [System.Web.HttpUtility]::HtmlEncode($o.Comparison)
                                                                $cmpClass = switch ($o.Comparison) { 'Matches' { 'badge-match' } 'Differs' { 'badge-diff' } 'Missing' { 'badge-miss' } default { 'badge-generic' } }
                                # Column order changed: move Tags column to the end
                                "<tr data-cmp='$cmp' data-tags='$dataTags' data-platform='$platEsc'><td data-colkey='BaselinePolicy'>$bpEsc</td><td data-colkey='DisplayName'>$dnEsc</td><td data-colkey='Platform'>$platEsc</td><td data-colkey='Description' class='text-muted small desc-cell'><div class='desc-text clamp'>$descEsc</div><button type='button' class='btn btn-link p-0 small more-btn' onclick='toggleDesc(this)'>More</button></td><td data-colkey='ExpectedValue' class='exp-val'>$expEsc</td><td data-colkey='ConfiguredPolicies' class='policies'>$polEsc</td><td data-colkey='ActualValues' class='actual-val'>$actEsc</td><td data-colkey='Comparison'><span class='cmp-badge $cmpClass'>$cmp</span></td><td data-colkey='Tags' class='tags-col'>$tagBadgesHtml</td></tr>"
                                                        }
                                                        $comparisonTableHtml = $comparisonRowsHtml -join "`n"

                                                        $extraRowsHtml = ''
                                                        if ($extraSettingsObjects.Count -gt 0) {
                                                                $extraRowsHtml = ($extraSettingsObjects | ForEach-Object {
                                                                        $polEsc  = [System.Web.HttpUtility]::HtmlEncode($_.PolicyName)
                                                                        $dnEsc   = [System.Web.HttpUtility]::HtmlEncode($_.DisplayName)
                                                                        $platEsc = [System.Web.HttpUtility]::HtmlEncode($_.Platform)
                                                                        $techEsc = [System.Web.HttpUtility]::HtmlEncode($_.Technologies)
                                                                        # (keywords handled via tag badges)
                                                                        $tagBadgesHtml = ''
                                                                        $dataTags = ''
                                                                        if($_.Keywords){
                                                                            $tags = $_.Keywords -split '\s*,\s*' | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique
                                                                            $dataTags = ($tags | ForEach-Object { $_.ToLower() }) -join ','
                                                                            $tagBadgesHtml = ($tags | ForEach-Object { $t = [System.Web.HttpUtility]::HtmlEncode($_); "<span class='badge me-1 tag-badge' data-tag='$t'>$t</span>" }) -join ''
                                                                        }
                                                                        $descEsc = [System.Web.HttpUtility]::HtmlEncode( ($_.Description -replace "`r?`n", ' ') )
                                                                        $valEsc  = [System.Web.HttpUtility]::HtmlEncode($_.ActualValue)
                                                                        # Move Tags column to end + add data-colkey attributes for column visibility toggles
                                                                        "<tr data-tags='$dataTags' data-platform='$platEsc'><td data-colkey='PolicyName'>$polEsc</td><td data-colkey='DisplayName'>$dnEsc</td><td data-colkey='Platform'>$platEsc</td><td data-colkey='Description' class='text-muted small desc-cell'><div class='desc-text clamp'>$descEsc</div><button type='button' class='btn btn-link p-0 small more-btn' onclick='toggleDesc(this)'>More</button></td><td data-colkey='ActualValue'>$valEsc</td><td data-colkey='Tags' class='tags-col'>$tagBadgesHtml</td></tr>"
                                                                }) -join "`n"
                                                        }

                                                        # Javascript search/filter snippet (proper here-string syntax)
                                                        $searchJs = @'
<script>
// (Lightweight stats script)
function filterBaselineTbl(){
    const q = document.getElementById('blSearch').value.toLowerCase();
    document.querySelectorAll('#baselineTable tbody tr').forEach(r=>{
        r.style.display = [...r.children].some(td => td.textContent.toLowerCase().includes(q)) ? '' : 'none';
    });
    document.querySelectorAll('#extraTable tbody tr').forEach(r=>{
        r.style.display = [...r.children].some(td => td.textContent.toLowerCase().includes(q)) ? '' : 'none';
    });
    updateSummaryStats();
}
function updateSummaryStats(){
    const rows = [...document.querySelectorAll('#baselineTable tbody tr')];
    const visible = rows.filter(r => r.style.display !== 'none');
    const totalVisible = visible.length;
    const countMatches = visible.filter(r => r.dataset.cmp === 'Matches').length;
    const countDiffers = visible.filter(r => r.dataset.cmp === 'Differs').length;
    const countMissing = visible.filter(r => r.dataset.cmp === 'Missing').length;
    const pct = (n)=> totalVisible ? ( (n/totalVisible)*100 ).toFixed(1).replace(/\.0$/,'') : '0';
    const setTxt = (id,val)=>{ const el=document.getElementById(id); if(el) el.textContent=val; };
    setTxt('totalBaselineCount', totalVisible);
    setTxt('matchesCount', countMatches);
    setTxt('differsCount', countDiffers);
    setTxt('missingCount', countMissing);
    setTxt('matchesPct', pct(countMatches));
    setTxt('differsPct', pct(countDiffers));
    setTxt('missingPct', pct(countMissing));
    // Only dynamic piece added: extra visible count (percentage relative to baseline totalVisible for context)
    const extraVisible = [...document.querySelectorAll('#extraTable tbody tr')].filter(r=> r.style.display !== 'none').length;
    setTxt('extraCount', extraVisible);
    setTxt('extraPct', totalVisible ? ( (extraVisible/totalVisible)*100 ).toFixed(1).replace(/\.0$/,'') : '0');
}
// Column visibility controls
document.addEventListener('DOMContentLoaded', () => {
    const colContainer = document.getElementById('columnVisibilityContainer');
    if(colContainer){
        const headers = document.querySelectorAll('#baselineTable thead th[data-colkey]');
        headers.forEach(h => {
            const key = h.getAttribute('data-colkey');
            const label = h.textContent.trim();
            const id = 'colvis_' + key;
            const div = document.createElement('div');
            div.className = 'form-check form-check-sm me-2';
            div.innerHTML = `<input class="form-check-input col-vis-cb" type="checkbox" id="${id}" data-colkey="${key}" checked><label class="form-check-label small" for="${id}">${label}</label>`;
            colContainer.appendChild(div);
        });
        colContainer.addEventListener('change', e => {
            const cb = e.target.closest('.col-vis-cb');
            if(!cb) return;
            const key = cb.getAttribute('data-colkey');
            toggleColumn(key, cb.checked);
        });
    }
    renderPlatformDistribution();
});

function toggleColumn(colKey, show){
    const sel = `#baselineTable [data-colkey='${colKey}'], #extraTable [data-colkey='${colKey}']`;
    document.querySelectorAll(sel).forEach(cell => { cell.style.display = show? '' : 'none'; });
}

function renderPlatformDistribution(){
    const container = document.getElementById('platformDistribution');
    if(!container) return;
    const rows = [...document.querySelectorAll('#baselineTable tbody tr')];
    const counts = {};
    rows.forEach(r => {
        const platCell = r.querySelector("td[data-colkey='Platform']") || r.children[2];
        if(!platCell) return;
        const p = platCell.textContent.trim() || 'Unknown';
        counts[p] = (counts[p]||0)+1;
    });
    const total = rows.length || 1;
    container.innerHTML = Object.keys(counts).sort().map(p=>{
        const c = counts[p];
        const pct = ((c/total)*100).toFixed(1);
        return `<span class="badge bg-light text-dark border">${p} <span class="text-muted">(${c} / ${pct}%)</span></span>`;
    }).join(' ');
}
function toggleDesc(btn){
    const wrapper = btn.previousElementSibling;
    if(wrapper.classList.contains('expanded')){
        wrapper.classList.remove('expanded');
        wrapper.classList.add('clamp');
        btn.textContent='More';
    } else {
        wrapper.classList.remove('clamp');
        wrapper.classList.add('expanded');
        btn.textContent='Less';
    }
}
function makeColsResizable(tableId){
    const table=document.getElementById(tableId); if(!table) return;
    const ths=[...table.querySelectorAll('thead th')];
    ths.forEach((th,idx)=>{
        if(th.querySelector('.col-resizer')) return;
        th.style.position='relative';
        const grip=document.createElement('span'); grip.className='col-resizer'; grip.title='Drag to resize'; th.appendChild(grip);
        let startX,startWidth;
        grip.addEventListener('mousedown',e=>{
            startX=e.pageX; startWidth=th.offsetWidth; document.documentElement.classList.add('resizing');
            function onMove(ev){ let w=startWidth+(ev.pageX-startX); if(w<60) w=60; th.style.width=w+'px'; table.querySelectorAll('tbody tr').forEach(r=>{ if(r.children[idx]) r.children[idx].style.width=w+'px'; }); }
            function onUp(){ document.removeEventListener('mousemove',onMove); document.removeEventListener('mouseup',onUp); document.documentElement.classList.remove('resizing'); }
            document.addEventListener('mousemove',onMove); document.addEventListener('mouseup',onUp); e.preventDefault(); e.stopPropagation();
        });
    });
}
function scrollToCategory(cat){
    const row=document.querySelector(`#baselineTable tbody tr[data-cmp="${cat}"]`); if(row){ row.scrollIntoView({behavior:'smooth',block:'start'}); }
}
function handleScrollTopBtn(){ const btn=document.getElementById('scrollTopBtn'); if(!btn) return; btn.style.display= window.scrollY>300 ? 'block':'none'; }
window.addEventListener('scroll',handleScrollTopBtn);
// Tag filtering logic
let currentSelectedTags = [];
let currentSelectedPlatforms = [];
function applyTagFilters(){
    const cbs = document.querySelectorAll('.tag-filter-cb');
    currentSelectedTags = [...cbs].filter(cb=>cb.checked).map(cb=>cb.value.toLowerCase());
    filterByTags();
    const dot = document.getElementById('activeFilterDot');
    if(dot){ dot.style.display = currentSelectedTags.length>0 ? 'inline-block':'none'; }
}
function filterByTags(){
    const rows = document.querySelectorAll('#baselineTable tbody tr, #extraTable tbody tr');
    rows.forEach(r=>{
        if(currentSelectedTags.length===0){ r.dataset.tagfiltered='0'; }
        else {
            const tags = (r.getAttribute('data-tags')||'').split(',').filter(x=>x);
            const hasAll = currentSelectedTags.every(t=> tags.includes(t));
            r.dataset.tagfiltered = hasAll ? '0':'1';
        }
    });
    applyCombinedVisibility();
}
function applyPlatformFilters(){
    const cbs = document.querySelectorAll('.platform-filter-cb');
    currentSelectedPlatforms = [...cbs].filter(cb=>cb.checked).map(cb=>cb.value.toLowerCase());
    filterByPlatform();
}
function filterByPlatform(){
    const rows = document.querySelectorAll('#baselineTable tbody tr, #extraTable tbody tr');
    rows.forEach(r=>{
        if(currentSelectedPlatforms.length===0){ r.dataset.platformfiltered='0'; }
        else {
            const plat = (r.getAttribute('data-platform')||'').toLowerCase();
            r.dataset.platformfiltered = currentSelectedPlatforms.includes(plat)? '0':'1';
        }
    });
    applyCombinedVisibility();
}
function clearPlatformFilters(){ document.querySelectorAll('.platform-filter-cb').forEach(cb=> cb.checked=false); currentSelectedPlatforms=[]; filterByPlatform(); }
function selectAllPlatformFilters(){ document.querySelectorAll('.platform-filter-cb').forEach(cb=> cb.checked=true); }
function applyCombinedVisibility(){
    const rows = document.querySelectorAll('#baselineTable tbody tr, #extraTable tbody tr');
    rows.forEach(r=>{
        if(r.dataset.searchHidden==='1' || r.dataset.tagfiltered==='1' || r.dataset.platformfiltered==='1'){ r.style.display='none'; }
        else { r.style.display=''; }
    });
    updateSummaryStats();
}
function clearTagFilters(){
    document.querySelectorAll('.tag-filter-cb').forEach(cb=> cb.checked=false);
    currentSelectedTags = [];
    filterByTags();
    const dot = document.getElementById('activeFilterDot'); if(dot){ dot.style.display='none'; }
}
function selectAllTagFilters(){ document.querySelectorAll('.tag-filter-cb').forEach(cb=> cb.checked=true); }
// Enhance existing search to mark rows hidden by search separately
const originalFilterBaselineTbl = filterBaselineTbl;
filterBaselineTbl = function(){
    const q = document.getElementById('blSearch').value.toLowerCase();
    document.querySelectorAll('#baselineTable tbody tr, #extraTable tbody tr').forEach(r=>{
        const match = [...r.children].some(td => td.textContent.toLowerCase().includes(q));
        r.dataset.searchHidden = match? '0':'1';
    });
    applyCombinedVisibility();
};
// Tag search filter (client-side for large tag lists)
document.addEventListener('input',function(e){
    if(e.target && e.target.id==='tagSearchInput'){
        const q = e.target.value.toLowerCase();
        document.querySelectorAll('#tagCheckboxContainer .form-check').forEach(div=>{
            const txt = div.textContent.toLowerCase();
            div.style.display = txt.includes(q)? '':'none';
        });
    }
});
// Click tag badge to toggle filter
document.addEventListener('click', function(e){
    const badge = e.target.closest('.tag-badge');
    if(!badge) return;
    const tag = badge.getAttribute('data-tag');
    if(!tag) return;
    // Find corresponding checkbox
    const cb = [...document.querySelectorAll('.tag-filter-cb')].find(c=> c.value.toLowerCase() === tag.toLowerCase());
    if(cb){
        // Toggle selection (if already only this tag selected, unselect; else select it and optionally keep others?)
        const currentlySelected = [...document.querySelectorAll('.tag-filter-cb')].filter(c=>c.checked).map(c=>c.value.toLowerCase());
        if(currentlySelected.length===1 && currentlySelected[0]===tag.toLowerCase()){
            cb.checked = false; // toggle off
        } else {
            // Select only this tag for quick focus
            document.querySelectorAll('.tag-filter-cb').forEach(c=> c.checked = false);
            cb.checked = true;
        }
    }
    applyTagFilters();
});
window.addEventListener('DOMContentLoaded',()=>{ makeColsResizable('baselineTable'); makeColsResizable('extraTable'); handleScrollTopBtn(); const t=document.getElementById('scrollTopBtn'); if(t){ t.addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'})); } });
</script>
'@
                                                        $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                                                        $tenant = try { (Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/organization' -Method GET).value[0].displayName } catch { 'Unknown Tenant' }

                                                        # Build HTML report (expandable here-string). NOTE: Keep opening @" on its own line to avoid parse errors.
                                                        $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'/>
<title>Security Baseline Comparison Report</title>
<meta name='viewport' content='width=device-width,initial-scale=1'/>
<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css' rel='stylesheet'/>
<link rel='icon' type='image/x-icon' href='data:image/x-icon;base64,$iconBase64'>
<style>
:root { --primary:#007ACC; --primary-dark:#005A9E; --muted:#888888; }
body{padding:24px;background:#f5f7fa;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;}
.header-logo{width:72px;height:72px;border-radius:12px;box-shadow:0 3px 8px rgba(0,0,0,.18);background:#fff;padding:6px;object-fit:contain;}
.header-bar{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;border-radius:12px;padding:18px 24px;box-shadow:0 4px 12px rgba(0,0,0,.15);}
table{font-size:.9rem;}
thead.sticky-top th{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;white-space:nowrap;position:sticky;top:0;z-index:20;}
.summary-badge{font-size:.75rem;padding:.45em .65em;border-radius:8px;font-weight:600;}
.badge-match{background:#198754;color:#fff;}
.badge-diff{background:#ffc107;color:#212529;}
.badge-miss{background:#dc3545;color:#fff;}
.badge-extra{background:#0dcaf0;color:#062c33;}
.cmp-badge{font-size:.70rem;padding:.30em .65em;border-radius:6px;font-weight:600;letter-spacing:.03em;white-space:nowrap;}
.cmp-badge.badge-match{background:#198754;color:#fff;}
.cmp-badge.badge-diff{background:#ffc107;color:#212529;}
.cmp-badge.badge-miss{background:#dc3545;color:#fff;}
.search-box{max-width:340px;}
.card{border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,.08);} 
.desc-text.clamp{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;max-height:4.5em;}
.desc-text.expanded{overflow:visible;max-height:none;}
.more-btn{display:block;margin-top:2px;}
thead th{position:relative;}
.col-resizer{position:absolute;top:0;right:0;width:6px;cursor:col-resize;user-select:none;height:100%;}
html.resizing, html.resizing * {cursor:col-resize !important;}
table#baselineTable, table#extraTable { table-layout:fixed; }
#baselineTable th, #baselineTable td, #extraTable th, #extraTable td { word-break:break-word; }
.desc-cell{max-width:420px;}
.policies,.actual-val,.exp-val{max-width:260px;}
.clickable{cursor:pointer;transition:transform .05s ease, box-shadow .15s ease;}
.clickable:hover{transform:translateY(-2px);box-shadow:0 4px 12px rgba(0,0,0,.18);}
.scroll-top-btn{position:fixed;bottom:24px;right:24px;display:none;z-index:999;box-shadow:0 3px 10px rgba(0,0,0,.25);} 
.advanced-filter-toggle{cursor:pointer;}
.tag-badge{font-size:.65rem;background:var(--primary)!important;color:#fff!important;padding:.35em .55em;border-radius:10px;display:inline-block;margin:0 4px 4px 0;line-height:1.2;transition:background-color .15s ease,box-shadow .15s ease;}
.tag-badge:hover{background:var(--primary-dark);color:#fff;}
.tags-col{min-width:200px;max-width:380px;white-space:normal !important;}
td.tags-col{vertical-align:top;}
td.tags-col{padding-top:.5rem;}
td.tags-col .tag-badge{position:relative;}
td.tags-col{overflow:visible;}
td.tags-col{display:flex;flex-wrap:wrap;align-items:flex-start;}
table#baselineTable td, table#extraTable td{vertical-align:top;}
/* Allow auto layout for better wrapping while keeping manual resize; start with auto then user-set width on drag */
table#baselineTable, table#extraTable { table-layout:auto; }
.offcanvas-tags{width:320px;}
.filter-active-indicator{width:10px;height:10px;border-radius:50%;background:#198754;display:inline-block;margin-left:6px;box-shadow:0 0 0 3px rgba(25,135,84,.25);}
</style>
</head>
<body>
    <div class='container-fluid'>
        <div class='header-bar mb-4 d-flex flex-wrap justify-content-between align-items-center gap-4'>
            <div class='d-flex align-items-center gap-3'>$iconImg<div><h1 class='h4 mb-1'>Security Baseline Comparison</h1><div class='small opacity-75'>Tenant: $tenant | Generated: $generated</div><div class='small opacity-75'>Baselines: $baselineNameList</div></div></div>
            <div class='search-box'><input id='blSearch' onkeyup='filterBaselineTbl()' class='form-control form-control-sm' placeholder='Search report...'></div>
        </div>
    <div class='row g-3 mb-4 align-items-stretch'>
            <div class='col-12 col-md-6 col-xl-3'>
                <div class='card h-100'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Total Baseline Settings</h6><div class='h4 mb-0'><span id='totalBaselineCount'>$totalBaselineSettings</span></div></div></div>
            </div>
            <div class='col-12 col-md-6 col-xl-3'>
                <div class='card h-100 clickable' onclick="scrollToCategory('Matches')"><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Matches</h6><div class='h4 mb-0'><span id='matchesCount'>$matchesCount</span> <span class='summary-badge badge-match ms-1'><span id='matchesPct'>$matchesPct</span>%</span></div></div></div>
            </div>
            <div class='col-12 col-md-6 col-xl-3'>
                <div class='card h-100 clickable' onclick="scrollToCategory('Differs')"><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Differs</h6><div class='h4 mb-0'><span id='differsCount'>$differsCount</span> <span class='summary-badge badge-diff ms-1'><span id='differsPct'>$differsPct</span>%</span></div></div></div>
            </div>
            <div class='col-12 col-md-6 col-xl-3'>
                <div class='card h-100 clickable' onclick="scrollToCategory('Missing')"><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Missing</h6><div class='h4 mb-0'><span id='missingCount'>$missingSettings</span> <span class='summary-badge badge-miss ms-1'><span id='missingPct'>$missingPct</span>%</span></div></div></div>
            </div>
            <div class='col-12 col-md-6 col-xl-3'>
                <div class='card h-100 clickable' onclick="scrollToCategory('Extra')"><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Extra (Policy Only)</h6><div class='h4 mb-0'><span id='extraCount'>$extraSettingsCount</span> <span class='summary-badge badge-extra ms-1'><span id='extraPct'>$extraPct</span>%</span></div></div></div>
            </div>
            <div class='col-12 col-md-6 col-xl-3 d-flex'>
                <div class='card h-100 w-100 advanced-filter-toggle' data-bs-toggle='offcanvas' data-bs-target='#offcanvasTags' aria-controls='offcanvasTags'>
                    <div class='card-body d-flex flex-column justify-content-center'>
                        <h6 class='text-uppercase small text-muted mb-2'>Tag Filters</h6>
                        <div class='h6 mb-0'>Select Tags <span id='activeFilterDot' style='display:none;' class='filter-active-indicator'></span></div>
                        <div class='small text-muted mt-1'>Click to refine by keywords</div>
                    </div>
                </div>
            </div>
            <div class='col-12'>
                <div class='card h-100'><div class='card-body'>
                    <h6 class='text-uppercase small text-muted mb-2'>Platform Distribution</h6>
                    <div id='platformDistribution' class='d-flex flex-wrap gap-2'></div>
                </div></div>
            </div>
        </div>
        <div class='offcanvas offcanvas-end offcanvas-tags' tabindex='-1' id='offcanvasTags' aria-labelledby='offcanvasTagsLabel'>
            <div class='offcanvas-header'>
                <h5 class='offcanvas-title' id='offcanvasTagsLabel'>Filter & Refine</h5>
                <button type='button' class='btn-close text-reset' data-bs-dismiss='offcanvas' aria-label='Close'></button>
            </div>
            <div class='offcanvas-body d-flex flex-column'>
                <div class='mb-3'>
                    <h6 class='text-muted text-uppercase small mb-2'>Column Visibility</h6>
                    <div id='columnVisibilityContainer' class='d-flex flex-wrap gap-2 mb-3'></div>
                    <h6 class='text-muted text-uppercase small mb-2 mt-2'>Tags</h6>
                    <input type='text' id='tagSearchInput' class='form-control form-control-sm mb-2' placeholder='Search tags...'>
                    <div class='overflow-auto border rounded p-2' style='max-height:180px' id='tagCheckboxContainer'>
                        $tagOptionsHtml
                    </div>
                    <div class='mt-2 d-flex gap-2 flex-wrap'>
                        <button class='btn btn-sm btn-primary' type='button' onclick='applyTagFilters()'>Apply</button>
                        <button class='btn btn-sm btn-outline-secondary' type='button' onclick='clearTagFilters()'>Clear</button>
                        <button class='btn btn-sm btn-outline-primary' type='button' onclick='selectAllTagFilters()'>Select All</button>
                    </div>
                </div>
                <hr/>
                <div class='mb-2'>
                    <h6 class='text-muted text-uppercase small mb-2'>Platforms</h6>
                    <div class='overflow-auto border rounded p-2' style='max-height:160px' id='platformCheckboxContainer'>
                        $platformFilterOptions
                    </div>
                    <div class='mt-2 d-flex gap-2 flex-wrap'>
                        <button class='btn btn-sm btn-primary' type='button' onclick='applyPlatformFilters()'>Apply</button>
                        <button class='btn btn-sm btn-outline-secondary' type='button' onclick='clearPlatformFilters()'>Clear</button>
                        <button class='btn btn-sm btn-outline-primary' type='button' onclick='selectAllPlatformFilters()'>Select All</button>
                    </div>
                </div>
            </div>
        </div>
        <div class='card mb-4'>
            <div class='card-body'>
                <h2 class='h5 text-primary mb-3'>Baseline Settings Comparison</h2>
                <div class='table-responsive'>
                    <table id='baselineTable' class='table table-sm table-hover align-middle'>
                        <thead class='sticky-top'><tr>
                            <th data-colkey='BaselinePolicy'>Baseline Policy</th>
                            <th data-colkey='DisplayName'>Display Name</th>
                            <th data-colkey='Platform'>Platform</th>
                            <th data-colkey='Description'>Description</th>
                            <th data-colkey='ExpectedValue'>Expected Value</th>
                            <th data-colkey='ConfiguredPolicies'>Configured Policies</th>
                            <th data-colkey='ActualValues'>Actual Values</th>
                            <th data-colkey='Comparison'>Result</th>
                            <th data-colkey='Tags'>Tags</th>
                        </tr></thead>
                        <tbody>
$comparisonTableHtml
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
$(if($extraSettingsObjects.Count -gt 0){ "<div class='card mb-5'><div class='card-body'><h2 class='h5 text-primary mb-3'>Extra Policy Settings (Not in Baseline)</h2><div class='table-responsive'><table id='extraTable' class='table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th data-colkey='PolicyName'>Policy Name(s)</th><th data-colkey='DisplayName'>Display Name</th><th data-colkey='Platform'>Platform</th><th data-colkey='Description'>Description</th><th data-colkey='ActualValue'>Actual Value</th><th data-colkey='Tags'>Tags</th></tr></thead><tbody>$extraRowsHtml</tbody></table></div></div></div>" } else { '' })
        <div class='text-center small text-muted mt-4 mb-3'>Generated by Intune Toolkit • Security Baseline Analysis</div>
    </div>
    <button id='scrollTopBtn' class='scroll-top-btn btn btn-primary btn-sm'>Top</button>
    $searchJs
    <script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>
</body>
</html>
"@

                                                        $html | Out-File -FilePath $dlgHtml.FileName -Encoding UTF8
                                                        Write-IntuneToolkitLog "Exported HTML baseline report to $($dlgHtml.FileName)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                                                        try {
                                                            Start-Process -FilePath $dlgHtml.FileName
                                                            Write-IntuneToolkitLog "Launched HTML report: $($dlgHtml.FileName)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                                                        } catch {
                                                            Write-IntuneToolkitLog "Failed to auto-open HTML report: $($_.Exception.Message)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                                                        }
                                                } catch {
                                                        Write-IntuneToolkitLog "Error exporting HTML report: $($_.Exception.Message)" -component "Comparison" -file "SecurityBaselineAnalysisButton.ps1"
                                                        [System.Windows.MessageBox]::Show("Failed to export HTML report: $($_.Exception.Message)","Error")
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
