<#
.SYNOPSIS
Performs a detailed security baseline analysis by retrieving configuration policy settings,
merging them, dynamically selecting and merging baseline policies from selected baseline folders,
comparing the two sets, and generating a Markdown report.

.DESCRIPTION
This script is triggered via a UI button click and performs the following tasks:
  - Validates that at least one configuration policy is selected.
  - Retrieves detailed policy settings from the Microsoft Graph API.
  - Merges all retrieved policy settings into a single collection for comparison.
  - Scans a baseline root folder (".\SupportFiles\Intune Baselines") to find available baseline folders.
  - If multiple baseline folders exist, displays a selection dialog (Show-BaselineSelectionDialog) for user baseline selection.
  - For each selected baseline folder, it reads JSON files from a "SettingsCatalog" subfolder.
    - If multiple JSON files exist, it prompts the user to select the baseline policies (using the JSON “name” property) to include.
  - Merges the baseline settings from the selected JSON files and tags each with its baseline policy name.
  - Loads a human-readable settings catalog (either from a local file or via the Graph API) for descriptions and display values.
  - Compares the merged baseline settings against the merged policy settings and computes statistics:
      - Matches: Settings that match the expected baseline value.
      - Differences: Settings that differ from the baseline.
      - Missing: Baseline settings that have no corresponding policy configuration.
      - Extra: Configured settings that are not defined in the baseline.
  - Generates a Markdown report containing the results and details.
  - Prompts the user to save the report using a Save File dialog.

.NOTES
Author: Maxime Guillemin
Date: 25/02/2025

.EXAMPLE
$SecurityBaselineAnalysisButton.Add_Click({
    # Executes the baseline analysis with detailed logging, baseline folder selection,
    # and baseline policy selection for folders containing multiple baseline policies.
})
#>

# Attach an event handler to the Security Baseline Analysis button click.
$SecurityBaselineAnalysisButton.Add_Click({
    try {
        # Log the button click event.
        Write-IntuneToolkitLog "SecurityBaselineAnalysisButton clicked" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        #############################################
        # Validate Selected Policies
        #############################################
        try {
            # Check if the user has selected at least one configuration policy.
            if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
                Write-IntuneToolkitLog "No policies selected for baseline analysis." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                [System.Windows.MessageBox]::Show("Please select one or more configuration policies.", "Information")
                return  # Exit if no policy is selected.
            }
            Write-IntuneToolkitLog "Selected policies count: $($PolicyDataGrid.SelectedItems.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        } catch {
            Write-IntuneToolkitLog "Error validating policy selection: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            throw  # Propagate exception to outer try/catch.
        }

        #############################################
        # Fetch and Merge Policy Settings via Graph API
        #############################################
        $mergedSettings = @()
        foreach ($policy in $PolicyDataGrid.SelectedItems) {
            try {
                # Determine the policy identifier (PolicyId property or id property).
                $policyId = if ($policy.PSObject.Properties["PolicyId"]) { $policy.PolicyId } else { $policy.id }
                Write-IntuneToolkitLog "Fetching details for policy: $policyId" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

                # Construct the URL to retrieve policy details including expanded settings.
                $url = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policyId)?`$expand=settings"
                Write-IntuneToolkitLog "Using URL: $url" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

                try {
                    # Make the GET request to Microsoft Graph API.
                    $policyDetail = Invoke-MgGraphRequest -Uri $url -Method GET
                    Write-IntuneToolkitLog "Policy details retrieved for $policyId" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                } catch {
                    Write-IntuneToolkitLog "Error fetching policy $policyId : $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    continue  # Skip this policy if an error occurs.
                }
                
                # Check if policy details and settings are present.
                if ($policyDetail -and $policyDetail.settings) {
                    # Ensure settings are treated as an array.
                    $settingsArray = if (-not ($policyDetail.settings -is [System.Array])) { @($policyDetail.settings) } else { $policyDetail.settings }
                    if ($settingsArray.Count -gt 0) {
                        Write-IntuneToolkitLog "Merging settings from policy: $($policyDetail.name) ($policyId) - Settings count: $($settingsArray.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        # Merge each setting into the collection.
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
        Write-IntuneToolkitLog "Total merged settings count: $($mergedSettings.Count)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"

        #############################################
        # Locate and Validate Baseline Folders
        #############################################
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
            # Retrieve all subdirectories under the baseline root.
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

        #############################################
        # Baseline Folder and Policy Selection
        #############################################
        try {
            if ($baselineFolders.Count -gt 1) {
                # If there are multiple baseline folders, prompt the user to select which ones to use.
                $selectedBaselineNames = Show-BaselineSelectionDialog -Items ($baselineFolders | ForEach-Object { $_.Name })
                if (-not $selectedBaselineNames) {
                    throw "User cancelled baseline selection or no baseline selected."
                }
                # Filter the baseline folders based on the user's selection.
                $selectedBaselineFolders = $baselineFolders | Where-Object { $selectedBaselineNames -contains $_.Name }
                Write-IntuneToolkitLog "User selected baseline(s): $($selectedBaselineNames -join ', ')" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            } else {
                # Only one baseline folder is available; select it by default.
                $selectedBaselineFolders = $baselineFolders
                Write-IntuneToolkitLog "Only one baseline folder found: $($baselineFolders[0].Name)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        } catch {
            Write-IntuneToolkitLog "Error during baseline selection: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            return
        }

        #############################################
        # Process Baseline Folder(s) and Load JSON Baseline Policies
        #############################################
        $mergedBaselineSettings = @()
        foreach ($folder in $selectedBaselineFolders) {
            try {
                Write-IntuneToolkitLog "Attempting to read JSON files from baseline folder: $($folder.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                # Build path to the SettingsCatalog subfolder.
                $settingsCatalogPath = Join-Path -Path $folder.FullName -ChildPath "SettingsCatalog"
                if (-not (Test-Path $settingsCatalogPath)) {
                    Write-IntuneToolkitLog "SettingsCatalog folder not found for baseline: $($folder.Name) at expected path: $settingsCatalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                    continue
                }
                Write-IntuneToolkitLog "Processing baseline folder: $($folder.Name) with catalog path: $settingsCatalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                # Get all JSON files in the SettingsCatalog folder.
                $catalogFiles = Get-ChildItem -Path $settingsCatalogPath -Filter *.json

                # If multiple JSON files are found, prompt the user to select the desired baseline policies.
                if ($catalogFiles.Count -gt 1) {
                    $policyNames = @()
                    foreach ($file in $catalogFiles) {
                        try {
                            # Parse JSON content to extract the baseline policy name.
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
                    # Display the baseline selection dialog with the extracted policy names.
                    $selectedPolicyNames = Show-BaselineSelectionDialog -Items $policyNames -Title "Select Baseline Policies from $($folder.Name)" -Height 500 -Width 600
                    if (-not $selectedPolicyNames) {
                        Write-IntuneToolkitLog "User did not select any baseline policies for folder: $($folder.Name)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        continue
                    }
                    # Filter catalog files to include only those with a matching baseline policy name.
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

                # Process each (filtered) catalog file.
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
                        # Extract the baseline policy name from the JSON file; if missing, use the folder name.
                        $baselinePolicyName = $jsonContent.name
                        if (-not $baselinePolicyName) {
                            Write-IntuneToolkitLog "No 'name' property found in $($file.FullName); using folder name $($folder.Name) as baseline policy name" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                            $baselinePolicyName = $folder.Name
                        } else {
                            Write-IntuneToolkitLog "Extracted baseline policy name '$baselinePolicyName' from $($file.FullName)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                        }
                        # Merge each setting from the baseline JSON file.
                        foreach ($setting in $jsonContent.settings) {
                            $mergedBaselineSettings += [PSCustomObject]@{
                                BaselinePolicy = $baselinePolicyName
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
        # Ensure at least one baseline setting was loaded.
        if ($mergedBaselineSettings.Count -eq 0) {
            Write-IntuneToolkitLog "No baseline settings found in selected baselines." -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            [System.Windows.MessageBox]::Show("No baseline settings found.", "Error")
            return
        }

        #############################################
        # Load or Fetch Human-Readable Settings Catalog
        #############################################
        try {
            $catalogPath = ".\SupportFiles\SettingsCatalog.json"
            if (Test-Path $catalogPath) {
                Write-IntuneToolkitLog "Loading settings catalog from $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                $catalogContent = Get-Content $catalogPath -Raw
                $Catalog = $catalogContent | ConvertFrom-Json
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
                Write-IntuneToolkitLog "Settings catalog fetched and saved to $catalogPath" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            }
        } catch {
            Write-IntuneToolkitLog "Error loading or fetching settings catalog: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
            return
        }

        #############################################
        # Compare Baseline Settings Against Configured Policy Settings
        #############################################
        $totalBaselineSettings = $mergedBaselineSettings.Count
        $missingSettings = 0
        $matchesCount   = 0
        $differsCount   = 0
        try {
            foreach ($baselineEntry in $mergedBaselineSettings) {
                try {
                    $baselineSetting = $baselineEntry.Setting
                    # Extract the unique setting definition ID from the baseline entry.
                    $baselineId = $baselineSetting.settingInstance.settingDefinitionId
                    # Get the expected value from the baseline (may be a choice value).
                    $expectedValue = $baselineSetting.settingInstance.choiceSettingValue.value
                    # Search for matching settings in the merged policy settings using the setting definition ID.
                    $matches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $baselineId }
                    if (-not $matches -or $matches.Count -eq 0) {
                        # Count as missing if no corresponding policy setting is found.
                        $missingSettings++
                    } else {
                        # Check if all matching settings have the expected value.
                        $allMatch = $true
                        foreach ($match in $matches) {
                            if ($match.Setting.settingInstance.choiceSettingValue.value -ne $expectedValue) {
                                $allMatch = $false
                                break
                            }
                        }
                        if ($allMatch) { 
                            $matchesCount++ 
                        } else { 
                            $differsCount++ 
                        }
                    }
                } catch {
                    Write-IntuneToolkitLog "Error comparing baseline setting (ID: $($baselineSetting.settingInstance.settingDefinitionId)): $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
                }
            }
        } catch {
            Write-IntuneToolkitLog "Error during baseline settings comparison: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }
        try {
            # Determine settings present in policy configurations that are not defined in the baseline.
            $mergedIds = $mergedSettings | ForEach-Object { $_.Setting.settingInstance.settingDefinitionId } | Sort-Object -Unique
            $baselineIds = $mergedBaselineSettings | ForEach-Object { $_.Setting.settingInstance.settingDefinitionId } | Sort-Object -Unique
            $extraIds = $mergedIds | Where-Object { $_ -notin $baselineIds }
            $extraSettingsCount = $extraIds.Count
        } catch {
            Write-IntuneToolkitLog "Error determining extra settings: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }

        #############################################
        # Generate the Markdown Report
        #############################################
        $reportLines = @()
        try {
            # Header with baseline folder name.
            $reportLines += "# $($folder.Name) Baseline Analysis Report"
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
            # For each baseline setting, add a row with details.
            foreach ($baselineEntry in $mergedBaselineSettings) {
                try {
                    $baselinePolicy = $baselineEntry.BaselinePolicy
                    $baselineSetting = $baselineEntry.Setting
                    $baselineId = $baselineSetting.settingInstance.settingDefinitionId
                    $expectedValue = $baselineSetting.settingInstance.choiceSettingValue.value
                    # Retrieve human-readable expected value and description from the settings catalog.
                    $readableExpected = if ($Catalog.Count -gt 0) { Get-SettingDisplayValue -settingValueId $expectedValue -Catalog $Catalog } else { $expectedValue }
                    $description = if ($Catalog.Count -gt 0) { Get-SettingDescription -settingId $baselineId -Catalog $Catalog } else { $baselineId }
                    $matches = $mergedSettings | Where-Object { $_.Setting.settingInstance.settingDefinitionId -eq $baselineId }
                    if (-not $matches -or $matches.Count -eq 0) {
                        # If no matching policy is found, mark the entry as missing.
                        $reportLines += "| $baselinePolicy | $description | $readableExpected | **Missing** | N/A | Missing |"
                    } else {
                        # List the names of the policies that include the setting.
                        $policyList = ($matches | ForEach-Object { "$($_.PolicyName)" }) -join "; "
                        # Retrieve actual configured values (both raw and human-readable).
                        $actualValuesRaw = ($matches | ForEach-Object { $_.Setting.settingInstance.choiceSettingValue.value }) -join "; "
                        $actualValues = if ($Catalog.Count -gt 0) { ($matches | ForEach-Object { Get-SettingDisplayValue -settingValueId $_.Setting.settingInstance.choiceSettingValue.value -Catalog $Catalog }) -join "; " } else { $actualValuesRaw }
                        # Determine if all matching policy settings meet the expected baseline value.
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
            # If there are extra settings configured in policies that aren’t part of the baseline, add them in a separate section.
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
            # Join all report lines into a single Markdown formatted string.
            $reportContent = $reportLines -join "`r`n"
        } catch {
            Write-IntuneToolkitLog "Error joining report lines: $($_.Exception.Message)" -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        }

        #############################################
        # Save the Generated Report Using a Save File Dialog
        #############################################
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $SaveDialog.Filter = "Markdown files (*.md)|*.md|All files (*.*)|*.*"
            $SaveDialog.Title = "Save Security Baseline Report As"
            if ($SaveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $SaveDialog.FileName -ne "") {
                # Write the Markdown report to the selected file.
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
        # Log any errors that occur during the overall execution of the baseline analysis.
        $errorMessage = "Failed to perform baseline analysis. Error: $($_.Exception.Message)"
        Write-IntuneToolkitLog $errorMessage -component "SecurityBaselineAnalysis-Button" -file "SecurityBaselineAnalysisButton.ps1"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
    }
})
