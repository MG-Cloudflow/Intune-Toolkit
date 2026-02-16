<#
.SYNOPSIS
Performs a comprehensive baseline comparison for Administrative Templates (Group Policy Configurations).
.DESCRIPTION
When the Administrative Template Baseline Comparison button is clicked, this handler:
  - Validates policy selection
  - Fetches definitionValues for selected policies via Graph API
  - Scans baseline root folder for available baseline folders
  - Prompts user to select baseline folder(s) and specific policies
  - Reads _Settings.json files from AdministrativeTemplates subfolder
  - Flattens both baseline and policy settings
  - Compares expected baseline values against actual policy values
  - Generates detailed Markdown report with matches, differences, missing, and extra settings
#>
$AdminTemplateBaselineComparisonButton.Add_Click({
    try {
        Write-IntuneToolkitLog "AdminTemplateBaselineComparisonButton clicked" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Validate Selected Policies
        #--------------------------------------------------------------------------------
        if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
            Write-IntuneToolkitLog "No policies selected for baseline comparison." -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            [System.Windows.MessageBox]::Show("Please select one or more Administrative Template policies.", "Information")
            return
        }
        Write-IntuneToolkitLog "Selected policies count: $($PolicyDataGrid.SelectedItems.Count)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Fetch and Merge Policy definitionValues via Graph API
        #--------------------------------------------------------------------------------
        $mergedSettings = @()
        foreach ($policy in $PolicyDataGrid.SelectedItems) {
            $policyId = if ($policy.PSObject.Properties["PolicyId"]) { $policy.PolicyId } else { $policy.id }
            Write-IntuneToolkitLog "Fetching details for policy: $policyId" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            
            # Fetch policy details
            $policyUrl = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($policyId)"
            try {
                $policyDetail = Invoke-MgGraphRequest -Uri $policyUrl -Method GET
                Write-IntuneToolkitLog "Policy details retrieved for $policyId" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            } catch {
                Write-IntuneToolkitLog "Error fetching policy $policyId : $($_.Exception.Message)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                continue
            }
            
            # Fetch definitionValues with expanded definition object
            $definitionValuesUrl = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($policyId)/definitionValues?`$expand=definition"
            try {
                $definitionValuesResponse = Invoke-MgGraphRequest -Uri $definitionValuesUrl -Method GET
                $policyDetail.definitionValues = if ($definitionValuesResponse.value) { $definitionValuesResponse.value } else { @() }
                Write-IntuneToolkitLog "Retrieved $($policyDetail.definitionValues.Count) definitionValues for policy $policyId" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            } catch {
                Write-IntuneToolkitLog "Error fetching definitionValues for policy $($policyId): $($_.Exception.Message)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                $policyDetail.definitionValues = @()
            }
            
            if ($policyDetail -and $policyDetail.definitionValues -and $policyDetail.definitionValues.Count -gt 0) {
                $settingsArray = if (-not ($policyDetail.definitionValues -is [System.Array])) { @($policyDetail.definitionValues) } else { $policyDetail.definitionValues }
                if ($settingsArray.Count -gt 0) {
                    Write-IntuneToolkitLog "Merging definitionValues from policy: $($policyDetail.displayName) ($policyId); Count: $($settingsArray.Count)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                    
                    # Fetch presentationValues for each definitionValue
                    foreach ($setting in $settingsArray) {
                        # Fetch presentationValues for this definitionValue
                        $defValueId = if ($setting.id) { $setting.id } elseif ($setting['id']) { $setting['id'] } else { $null }
                        if ($defValueId) {
                            try {
                                $presValuesUrl = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations/$($policyId)/definitionValues('$defValueId')/presentationValues"
                                $presValuesResponse = Invoke-MgGraphRequest -Uri $presValuesUrl -Method GET
                                if ($presValuesResponse.value) {
                                    $setting.presentationValues = $presValuesResponse.value
                                    Write-IntuneToolkitLog "Fetched $($presValuesResponse.value.Count) presentationValues for definitionValue $defValueId" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                                }
                            } catch {
                                Write-IntuneToolkitLog "Error fetching presentationValues for definitionValue $($defValueId): $($_.Exception.Message)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                            }
                        }
                        
                        $mergedSettings += [PSCustomObject]@{
                            PolicyId   = $policyDetail.id
                            PolicyName = $policyDetail.displayName
                            Setting    = $setting
                        }
                    }
                } else {
                    Write-IntuneToolkitLog "Policy $policyId returned an empty definitionValues array." -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                }
            } else {
                Write-IntuneToolkitLog "Policy $policyId has no definitionValues to merge." -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            }
        }
        Write-IntuneToolkitLog "Total merged policy settings count: $($mergedSettings.Count)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Flatten Policy Settings
        #--------------------------------------------------------------------------------
        if ($mergedSettings.Count -eq 0) {
            Write-IntuneToolkitLog "No policy settings to flatten. Selected policies may have no configured settings." -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            [System.Windows.MessageBox]::Show("Selected policies have no configured definitionValues. Please select policies that have settings configured.", "No Settings Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        
        $definitionCache = @{}
        $flattenedPolicy = Flatten-AdminTemplateSettings -MergedPolicy $mergedSettings -DefinitionCache $definitionCache
        Write-IntuneToolkitLog "Flattened policy settings count: $($flattenedPolicy.Count)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Locate and Validate Baseline Folders
        #--------------------------------------------------------------------------------
        $baselineRootPath = ".\SupportFiles\Intune Baselines"
        if (-not (Test-Path $baselineRootPath)) {
            Write-IntuneToolkitLog "Baseline folder not found at $baselineRootPath" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            [System.Windows.MessageBox]::Show("Baseline folder not found at $baselineRootPath", "Error")
            return
        }
        Write-IntuneToolkitLog "Baseline root path found: $baselineRootPath" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
        
        $baselineFolders = Get-ChildItem -Path $baselineRootPath -Directory
        if ($baselineFolders.Count -eq 0) {
            Write-IntuneToolkitLog "No baseline folders found in $baselineRootPath" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            [System.Windows.MessageBox]::Show("No baseline folders found", "Error")
            return
        }
        Write-IntuneToolkitLog "Found $($baselineFolders.Count) baseline folder(s) in $baselineRootPath" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Baseline Folder Selection
        #--------------------------------------------------------------------------------
        if ($baselineFolders.Count -gt 1) {
            $selectedBaselineNames = Show-BaselineSelectionDialog -Items ($baselineFolders | ForEach-Object { $_.Name })
            if (-not $selectedBaselineNames) {
                Write-IntuneToolkitLog "User cancelled baseline selection or no baseline selected." -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                return
            }
            $selectedBaselineFolders = $baselineFolders | Where-Object { $selectedBaselineNames -contains $_.Name }
            Write-IntuneToolkitLog "User selected baseline(s): $($selectedBaselineNames -join ', ')" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
        } else {
            $selectedBaselineFolders = $baselineFolders
            Write-IntuneToolkitLog "Only one baseline folder found: $($baselineFolders[0].Name)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
        }

        #--------------------------------------------------------------------------------
        # Process Baseline Folders and Load _Settings.json Files
        #--------------------------------------------------------------------------------
        $mergedBaselineSettings = @()
        foreach ($folder in $selectedBaselineFolders) {
            Write-IntuneToolkitLog "Processing baseline folder: $($folder.Name)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            $adminTemplatesPath = Join-Path -Path $folder.FullName -ChildPath "AdministrativeTemplates"
            if (-not (Test-Path $adminTemplatesPath)) {
                Write-IntuneToolkitLog "AdministrativeTemplates folder not found for baseline: $($folder.Name) at expected path: $adminTemplatesPath" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                continue
            }
            Write-IntuneToolkitLog "Found AdministrativeTemplates folder: $adminTemplatesPath" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            
            # Get all _Settings.json files
            $settingsFiles = Get-ChildItem -Path $adminTemplatesPath -Filter "*_Settings.json"
            Write-IntuneToolkitLog "Found $($settingsFiles.Count) _Settings.json file(s) in $adminTemplatesPath" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

            # If multiple files exist, prompt user to select which baseline policies to use
            if ($settingsFiles.Count -gt 1) {
                # Extract policy names from file names (remove _Settings.json suffix)
                $policyNames = $settingsFiles | ForEach-Object { $_.BaseName -replace '_Settings$', '' }
                $selectedPolicyNames = Show-BaselineSelectionDialog -Items $policyNames -Title "Select Baseline Policies from $($folder.Name)" -Height 500 -Width 600
                if (-not $selectedPolicyNames) {
                    Write-IntuneToolkitLog "User did not select any baseline policies for folder: $($folder.Name)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                    continue
                }
                # Filter files based on selection
                $settingsFiles = $settingsFiles | Where-Object {
                    $baseName = $_.BaseName -replace '_Settings$', ''
                    return $selectedPolicyNames -contains $baseName
                }
            }

            # Process each _Settings.json file
            foreach ($file in $settingsFiles) {
                try {
                    Write-IntuneToolkitLog "Loading baseline file: $($file.FullName)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                    $jsonContent = Get-Content $file.FullName -Raw | ConvertFrom-Json
                    
                    # Extract policy name from filename (remove _Settings.json)
                    $baselinePolicyName = $file.BaseName -replace '_Settings$', ''
                    Write-IntuneToolkitLog "Extracted baseline policy name: $baselinePolicyName" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                    
                    # _Settings.json files contain an array of definitionValues
                    $settingsArray = if ($jsonContent -is [System.Array]) { $jsonContent } else { @($jsonContent) }
                    foreach ($setting in $settingsArray) {
                        $mergedBaselineSettings += [PSCustomObject]@{
                            BaselinePolicy = $baselinePolicyName
                            Setting        = $setting
                        }
                    }
                    Write-IntuneToolkitLog "Merged $($settingsArray.Count) baseline settings from file: $($file.Name)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                } catch {
                    Write-IntuneToolkitLog "Error processing baseline file $($file.FullName): $($_.Exception.Message)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                }
            }
        }
        
        if ($mergedBaselineSettings.Count -eq 0) {
            Write-IntuneToolkitLog "No baseline settings found in selected baselines." -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            [System.Windows.MessageBox]::Show("No baseline settings found.", "Error")
            return
        }
        Write-IntuneToolkitLog "Total merged baseline settings: $($mergedBaselineSettings.Count)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Flatten Baseline Settings
        #--------------------------------------------------------------------------------
        $flattenedBaseline = Flatten-AdminTemplateSettings -MergedPolicy $mergedBaselineSettings -DefinitionCache $definitionCache
        Write-IntuneToolkitLog "Flattened baseline settings count: $($flattenedBaseline.Count)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Compare Baseline vs Policy Settings
        #--------------------------------------------------------------------------------
        $comparisonResults = @()
        $matchCount = 0
        $differCount = 0
        $missingCount = 0

        # Build lookup dictionary for policy settings
        $policyLookup = @{}
        foreach ($ps in $flattenedPolicy) {
            $key = $ps.DefinitionGuid
            if (-not $policyLookup.ContainsKey($key)) {
                $policyLookup[$key] = @()
            }
            $policyLookup[$key] += $ps
        }

        # Compare each baseline setting against policy
        foreach ($bs in $flattenedBaseline) {
            $guid = $bs.DefinitionGuid
            $baselineValue = $bs.ConfiguredValue
            $settingName = $bs.SettingName
            $description = $bs.Description
            $categoryPath = $bs.CategoryPath
            $baselinePolicy = $bs.PolicyName

            if ($policyLookup.ContainsKey($guid)) {
                # Setting exists in policy
                $policyEntries = $policyLookup[$guid]
                $actualValues = ($policyEntries | ForEach-Object { $_.ConfiguredValue }) | Select-Object -Unique
                $actualValueDisplay = ($actualValues -join "; ")
                $configuredPolicies = (($policyEntries | ForEach-Object { $_.PolicyName }) | Select-Object -Unique) -join "; "

                # Compare values
                $match = $false
                foreach ($actualValue in $actualValues) {
                    if ($actualValue -eq $baselineValue) {
                        $match = $true
                        break
                    }
                }

                if ($match) {
                    $comparisonResult = "✓ Match"
                    $matchCount++
                } else {
                    $comparisonResult = "✗ Different"
                    $differCount++
                }

                $comparisonResults += [PSCustomObject]@{
                    BaselinePolicy    = $baselinePolicy
                    SettingName       = $settingName
                    CategoryPath      = $categoryPath
                    Description       = $description
                    ExpectedValue     = $baselineValue
                    ConfiguredPolicies = $configuredPolicies
                    ActualValue       = $actualValueDisplay
                    ComparisonResult  = $comparisonResult
                    DefinitionGuid    = $guid
                }
            } else {
                # Setting missing from policy
                $comparisonResult = "⚠ Missing"
                $missingCount++
                $comparisonResults += [PSCustomObject]@{
                    BaselinePolicy    = $baselinePolicy
                    SettingName       = $settingName
                    CategoryPath      = $categoryPath
                    Description       = $description
                    ExpectedValue     = $baselineValue
                    ConfiguredPolicies = "Not Configured"
                    ActualValue       = "Not Configured"
                    ComparisonResult  = $comparisonResult
                    DefinitionGuid    = $guid
                }
            }
        }

        # Find extra policy settings not in baseline
        $baselineLookup = @{}
        foreach ($bs in $flattenedBaseline) {
            $baselineLookup[$bs.DefinitionGuid] = $true
        }

        $extraSettings = @()
        foreach ($ps in $flattenedPolicy) {
            if (-not $baselineLookup.ContainsKey($ps.DefinitionGuid)) {
                $extraSettings += $ps
            }
        }

        Write-IntuneToolkitLog "Comparison complete - Matches: $matchCount, Differences: $differCount, Missing: $missingCount, Extra: $($extraSettings.Count)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Generate Markdown Report
        #--------------------------------------------------------------------------------
        $md = @()
        $md += "# Administrative Template Baseline Comparison Report"
        $md += ""
        $md += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $md += ""
        $md += "## Summary"
        $md += ""
        $md += "| Metric | Count |"
        $md += "|--------|-------|"
        $md += "| Total Baseline Settings | $($flattenedBaseline.Count) |"
        $md += "| Matches (✓) | $matchCount |"
        $md += "| Differences (✗) | $differCount |"
        $md += "| Missing (⚠) | $missingCount |"
        $md += "| Extra Policy Settings | $($extraSettings.Count) |"
        $md += ""

        # Matches section
        if ($matchCount -gt 0) {
            $md += "## ✓ Matching Settings ($matchCount)"
            $md += ""
            $md += "| Baseline Policy | Setting | Category | Expected Value | Configured In |"
            $md += "|----------------|---------|----------|----------------|---------------|"
            foreach ($r in ($comparisonResults | Where-Object { $_.ComparisonResult -eq "✓ Match" })) {
                $md += "| $($r.BaselinePolicy) | $($r.SettingName) | $($r.CategoryPath) | $($r.ExpectedValue) | $($r.ConfiguredPolicies) |"
            }
            $md += ""
        }

        # Differences section
        if ($differCount -gt 0) {
            $md += "## ✗ Different Settings ($differCount)"
            $md += ""
            $md += "| Baseline Policy | Setting | Category | Expected Value | Actual Value | Configured In |"
            $md += "|----------------|---------|----------|----------------|--------------|---------------|"
            foreach ($r in ($comparisonResults | Where-Object { $_.ComparisonResult -eq "✗ Different" })) {
                $md += "| $($r.BaselinePolicy) | $($r.SettingName) | $($r.CategoryPath) | $($r.ExpectedValue) | $($r.ActualValue) | $($r.ConfiguredPolicies) |"
            }
            $md += ""
        }

        # Missing section
        if ($missingCount -gt 0) {
            $md += "## ⚠ Missing Settings ($missingCount)"
            $md += ""
            $md += "| Baseline Policy | Setting | Category | Expected Value | Description |"
            $md += "|----------------|---------|----------|----------------|-------------|"
            foreach ($r in ($comparisonResults | Where-Object { $_.ComparisonResult -eq "⚠ Missing" })) {
                $md += "| $($r.BaselinePolicy) | $($r.SettingName) | $($r.CategoryPath) | $($r.ExpectedValue) | $($r.Description) |"
            }
            $md += ""
        }

        # Extra settings section
        if ($extraSettings.Count -gt 0) {
            $md += "## Additional Policy Settings Not in Baseline ($($extraSettings.Count))"
            $md += ""
            $md += "| Policy | Setting | Category | Configured Value |"
            $md += "|--------|---------|----------|------------------|"
            foreach ($es in $extraSettings) {
                $md += "| $($es.PolicyName) | $($es.SettingName) | $($es.CategoryPath) | $($es.ConfiguredValue) |"
            }
            $md += ""
        }

        # Full details section
        $md += "## Complete Comparison Details"
        $md += ""
        $md += "| Result | Baseline Policy | Setting | Category | Description | Expected Value | Actual Value | Configured In |"
        $md += "|--------|----------------|---------|----------|-------------|----------------|--------------|---------------|"
        foreach ($r in $comparisonResults) {
            $md += "| $($r.ComparisonResult) | $($r.BaselinePolicy) | $($r.SettingName) | $($r.CategoryPath) | $($r.Description) | $($r.ExpectedValue) | $($r.ActualValue) | $($r.ConfiguredPolicies) |"
        }

        #--------------------------------------------------------------------------------
        # Show Export Format Selection Dialog
        #--------------------------------------------------------------------------------
        $selectedFormats = Show-ExportOptionsDialog
        if (-not $selectedFormats -or $selectedFormats.Count -eq 0) {
            Write-IntuneToolkitLog "User cancelled export format selection" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
            return
        }
        Write-IntuneToolkitLog "User selected formats: $($selectedFormats -join ', ')" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"

        #--------------------------------------------------------------------------------
        # Generate Reports in Selected Formats
        #--------------------------------------------------------------------------------
        Add-Type -AssemblyName System.Windows.Forms
        $baseName = "AdminTemplateBaselineComparison_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
        
        foreach ($format in $selectedFormats) {
            switch ($format) {
                'Markdown' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter = 'Markdown (*.md)|*.md|All (*.*)|*.*'
                    $dlg.Title = 'Save Administrative Template Baseline Comparison Report (Markdown)'
                    $dlg.FileName = "$baseName.md"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $md -join "`r`n" | Out-File -FilePath $dlg.FileName -Encoding UTF8
                        Write-IntuneToolkitLog "Markdown report saved to: $($dlg.FileName)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                        try { Start-Process -FilePath $dlg.FileName } catch {}
                    }
                }
                'CSV' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter = 'CSV (*.csv)|*.csv|All (*.*)|*.*'
                    $dlg.Title = 'Save Administrative Template Baseline Comparison Report (CSV)'
                    $dlg.FileName = "$baseName.csv"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        # Create CSV export with all comparison details
                        $csvData = @()
                        foreach ($r in $comparisonResults) {
                            $csvData += [PSCustomObject]@{
                                Result = $r.ComparisonResult
                                BaselinePolicy = $r.BaselinePolicy
                                Setting = $r.SettingName
                                Category = $r.CategoryPath
                                Description = $r.Description
                                ExpectedValue = $r.ExpectedValue
                                ActualValue = $r.ActualValue
                                ConfiguredIn = $r.ConfiguredPolicies
                                DefinitionGuid = $r.DefinitionGuid
                            }
                        }
                        # Add extra settings
                        foreach ($es in $extraSettings) {
                            $csvData += [PSCustomObject]@{
                                Result = "Extra (Not in Baseline)"
                                BaselinePolicy = ""
                                Setting = $es.SettingName
                                Category = $es.CategoryPath
                                Description = $es.Description
                                ExpectedValue = ""
                                ActualValue = $es.ConfiguredValue
                                ConfiguredIn = $es.PolicyName
                                DefinitionGuid = $es.DefinitionGuid
                            }
                        }
                        $csvData | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
                        Write-IntuneToolkitLog "CSV report saved to: $($dlg.FileName)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                    }
                }
                'HTML' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter = 'HTML (*.html)|*.html|All (*.*)|*.*'
                    $dlg.Title = 'Save Administrative Template Baseline Comparison Report (HTML)'
                    $dlg.FileName = "$baseName.html"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        try {
                            Add-Type -AssemblyName System.Web
                        } catch {}
                        
                        # Calculate percentages
                        function _pct($n, $d) { if ($d) { [math]::Round(($n / $d) * 100, 1) } else { 0 } }
                        $matchPct = _pct $matchCount $flattenedBaseline.Count
                        $differPct = _pct $differCount $flattenedBaseline.Count
                        $missingPct = _pct $missingCount $flattenedBaseline.Count

                        # Build HTML rows
                        $matchRows = ""
                        $differRows = ""
                        $missingRows = ""
                        $extraRows = ""
                        
                        foreach ($r in $comparisonResults) {
                            $baselineEsc = [System.Web.HttpUtility]::HtmlEncode($r.BaselinePolicy)
                            $settingEsc = [System.Web.HttpUtility]::HtmlEncode($r.SettingName)
                            $categoryEsc = [System.Web.HttpUtility]::HtmlEncode($r.CategoryPath)
                            $descRaw = if ($r.Description) { ($r.Description -replace "`r?`n", " ") } else { "" }
                            $descEsc = [System.Web.HttpUtility]::HtmlEncode($descRaw)
                            $expectedEsc = [System.Web.HttpUtility]::HtmlEncode($r.ExpectedValue)
                            $actualEsc = [System.Web.HttpUtility]::HtmlEncode($r.ActualValue)
                            $configuredEsc = [System.Web.HttpUtility]::HtmlEncode($r.ConfiguredPolicies)
                            
                            $row = "<tr><td data-colkey='Baseline'>$baselineEsc</td><td data-colkey='Setting'>$settingEsc</td><td data-colkey='Category'>$categoryEsc</td><td data-colkey='Description' class='text-muted small desc-cell'><div class='desc-text clamp'>$descEsc</div><button type='button' class='btn btn-link p-0 small more-btn' onclick='toggleDesc(this)'>More</button></td><td data-colkey='Expected'>$expectedEsc</td><td data-colkey='Actual'>$actualEsc</td><td data-colkey='ConfiguredIn'>$configuredEsc</td></tr>"
                            
                            switch ($r.ComparisonResult) {
                                "✓ Match" { $matchRows += $row }
                                "✗ Different" { $differRows += $row }
                                "⚠ Missing" { $missingRows += $row }
                            }
                        }
                        
                        foreach ($es in $extraSettings) {
                            $policyEsc = [System.Web.HttpUtility]::HtmlEncode($es.PolicyName)
                            $settingEsc = [System.Web.HttpUtility]::HtmlEncode($es.SettingName)
                            $categoryEsc = [System.Web.HttpUtility]::HtmlEncode($es.CategoryPath)
                            $descRaw = if ($es.Description) { ($es.Description -replace "`r?`n", " ") } else { "" }
                            $descEsc = [System.Web.HttpUtility]::HtmlEncode($descRaw)
                            $valueEsc = [System.Web.HttpUtility]::HtmlEncode($es.ConfiguredValue)
                            
                            $extraRows += "<tr><td data-colkey='Policy'>$policyEsc</td><td data-colkey='Setting'>$settingEsc</td><td data-colkey='Category'>$categoryEsc</td><td data-colkey='Description' class='text-muted small desc-cell'><div class='desc-text clamp'>$descEsc</div><button type='button' class='btn btn-link p-0 small more-btn' onclick='toggleDesc(this)'>More</button></td><td data-colkey='Value'>$valueEsc</td></tr>"
                        }

                        # Icon (optional)
                        $iconBase64 = ''
                        $headerLogoBase64 = ''
                        $headerLogoMime = 'image/png'
                        $iconPathIco = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.ico'
                        if (Test-Path $iconPathIco) { $bytesIco = [System.IO.File]::ReadAllBytes($iconPathIco); $iconBase64 = [Convert]::ToBase64String($bytesIco) }
                        $logoPathPng = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.png'
                        if (Test-Path $logoPathPng) { $logoBytes = [System.IO.File]::ReadAllBytes($logoPathPng); $headerLogoBase64 = [Convert]::ToBase64String($logoBytes) } elseif ($iconBase64) { $headerLogoBase64 = $iconBase64; $headerLogoMime = 'image/x-icon' }
                        $iconImg = if ($headerLogoBase64) { "<img src='data:$headerLogoMime;base64,$headerLogoBase64' class='header-logo' alt='Intune Toolkit Logo'>" } else { '' }

                        $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        $tenant = try { (Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/organization' -Method GET).value[0].displayName } catch { 'Unknown Tenant' }
                        $differPct = _pct $differCount $flattenedBaseline.Count
                        $missingPct = _pct $missingCount $flattenedBaseline.Count
                        
                        $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'/>
<title>Administrative Template Baseline Comparison</title>
<meta name='viewport' content='width=device-width,initial-scale=1'/>
<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css' rel='stylesheet'/>
<link rel='icon' type='image/x-icon' href='data:image/x-icon;base64,$iconBase64'>
<style>
:root { --primary:#007ACC; --primary-dark:#005A9E; --match:#198754; --diff:#dc3545; --missing:#ffc107; }
body{padding:24px;background:#f5f7fa;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;}
.header-logo{width:64px;height:64px;border-radius:12px;box-shadow:0 3px 8px rgba(0,0,0,.18);background:#fff;padding:6px;object-fit:contain;}
.header-bar{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;border-radius:12px;padding:18px 24px;box-shadow:0 4px 12px rgba(0,0,0,.15);}
table{font-size:.9rem;}
thead.sticky-top th{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;white-space:nowrap;position:sticky;top:0;z-index:20;}
.summary-badge{font-size:.75rem;padding:.45em .65em;border-radius:8px;font-weight:600;}
.badge-match{background:var(--match);color:#fff;}
.badge-diff{background:var(--diff);color:#fff;}
.badge-missing{background:var(--missing);color:#212529;}
.search-box{max-width:340px;}
.card{border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,.08);}
.desc-text.clamp{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;max-height:4.5em;}
.desc-text.expanded{overflow:visible;max-height:none;}
.more-btn{display:block;margin-top:2px;}
thead th{position:relative;}
.col-resizer{position:absolute;top:0;right:0;width:6px;cursor:col-resize;user-select:none;height:100%;}
html.resizing, html.resizing * {cursor:col-resize !important;}
#settingsTable { table-layout:auto; }
#settingsTable th,#settingsTable td{word-break:break-word;vertical-align:top;}
.desc-cell{max-width:420px;}
.scroll-top-btn{position:fixed;bottom:24px;right:24px;display:none;z-index:999;box-shadow:0 3px 10px rgba(0,0,0,.25);}
.nav-pills .nav-link{color:#495057;border-radius:8px;}
.nav-pills .nav-link.active{background-color:var(--primary);color:#fff;}
.card-clickable{cursor:pointer;transition:transform .2s,box-shadow .2s;}
.card-clickable:hover{transform:translateY(-4px);box-shadow:0 6px 16px rgba(0,0,0,.15);}
.card-clickable.active{box-shadow:0 0 0 3px rgba(0,122,204,.3);transform:scale(1.02);}
</style>
</head>
<body>
<div class='container-fluid'>
    <div class='header-bar mb-4 d-flex flex-wrap justify-content-between align-items-center gap-4'>
    <div class='d-flex align-items-center gap-3'>$iconImg<div><h1 class='h4 mb-1'>Baseline Comparison Report</h1><div class='small opacity-75'>Tenant: $tenant | Generated: $generated</div></div></div>
    <div class='search-box'><input id='blSearch' onkeyup='filterTables()' class='form-control form-control-sm' placeholder='Search report...'></div>
    </div>
    <div class='row g-3 mb-4 align-items-stretch'>
        <div class='col-12 col-md-6 col-xl-2-4'>
            <div class='card h-100 card-clickable' data-bs-toggle='pill' data-bs-target='#all' role='button'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Total Baseline</h6><div class='h4 mb-0'>$($flattenedBaseline.Count)</div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2-4'>
            <div class='card h-100 card-clickable' data-bs-toggle='pill' data-bs-target='#matches' role='button'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>✓ Matches</h6><div class='h4 mb-0'>$matchCount <span class='summary-badge badge-match ms-1'>$matchPct%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2-4'>
            <div class='card h-100 card-clickable' data-bs-toggle='pill' data-bs-target='#differences' role='button'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>✗ Differences</h6><div class='h4 mb-0'>$differCount <span class='summary-badge badge-diff ms-1'>$differPct%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2-4'>
            <div class='card h-100 card-clickable' data-bs-toggle='pill' data-bs-target='#missing' role='button'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>⚠ Missing</h6><div class='h4 mb-0'>$missingCount <span class='summary-badge badge-missing ms-1'>$missingPct%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2-4'>
            <div class='card h-100 card-clickable' data-bs-toggle='pill' data-bs-target='#extra' role='button'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>+ Extra</h6><div class='h4 mb-0'>$($extraSettings.Count)</div></div></div>
        </div>
    </div>
    <div class='tab-content' id='sectionTabContent'>
        <div class='tab-pane fade show active' id='all' role='tabpanel'>
            $(if ($matchCount -gt 0) { @"
            <div class='card mb-4'>
                <div class='card-body'>
                    <h2 class='h5 text-success mb-3'>✓ Matching Settings ($matchCount)</h2>
                    <div class='table-responsive'>
                        <table id='matchTable' class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th data-colkey='Baseline'>Baseline Policy</th>
                                <th data-colkey='Setting'>Setting</th>
                                <th data-colkey='Category'>Category</th>
                                <th data-colkey='Description'>Description</th>
                                <th data-colkey='Expected'>Expected Value</th>
                                <th data-colkey='Actual'>Actual Value</th>
                                <th data-colkey='ConfiguredIn'>Configured In</th>
                            </tr></thead>
                            <tbody>$matchRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ })
            $(if ($differCount -gt 0) { @"
            <div class='card mb-4'>
                <div class='card-body'>
                    <h2 class='h5 text-danger mb-3'>✗ Different Settings ($differCount)</h2>
                    <div class='table-responsive'>
                        <table id='differTable' class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th data-colkey='Baseline'>Baseline Policy</th>
                                <th data-colkey='Setting'>Setting</th>
                                <th data-colkey='Category'>Category</th>
                                <th data-colkey='Description'>Description</th>
                                <th data-colkey='Expected'>Expected Value</th>
                                <th data-colkey='Actual'>Actual Value</th>
                                <th data-colkey='ConfiguredIn'>Configured In</th>
                            </tr></thead>
                            <tbody>$differRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ })
            $(if ($missingCount -gt 0) { @"
            <div class='card mb-4'>
                <div class='card-body'>
                    <h2 class='h5 text-warning mb-3'>⚠ Missing Settings ($missingCount)</h2>
                    <div class='table-responsive'>
                        <table id='missingTable' class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th data-colkey='Baseline'>Baseline Policy</th>
                                <th data-colkey='Setting'>Setting</th>
                                <th data-colkey='Category'>Category</th>
                                <th data-colkey='Description'>Description</th>
                                <th data-colkey='Expected'>Expected Value</th>
                                <th data-colkey='Actual'>Actual Value</th>
                                <th data-colkey='ConfiguredIn'>Configured In</th>
                            </tr></thead>
                            <tbody>$missingRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ })
            $(if ($extraSettings.Count -gt 0) { @"
            <div class='card mb-4'>
                <div class='card-body'>
                    <h2 class='h5 text-primary mb-3'>+ Additional Settings Not in Baseline ($($extraSettings.Count))</h2>
                    <div class='table-responsive'>
                        <table id='extraTable' class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th data-colkey='Policy'>Policy</th>
                                <th data-colkey='Setting'>Setting</th>
                                <th data-colkey='Category'>Category</th>
                                <th data-colkey='Description'>Description</th>
                                <th data-colkey='Value'>Configured Value</th>
                            </tr></thead>
                            <tbody>$extraRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ })
        </div>
        <div class='tab-pane fade' id='matches' role='tabpanel'>
            $(if ($matchCount -gt 0) { @"
            <div class='card'>
                <div class='card-body'>
                    <div class='table-responsive'>
                        <table class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th>Baseline Policy</th><th>Setting</th><th>Category</th><th>Description</th><th>Expected Value</th><th>Actual Value</th><th>Configured In</th>
                            </tr></thead>
                            <tbody>$matchRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ } else { "<p class='text-muted'>No matching settings found.</p>" })
        </div>
        <div class='tab-pane fade' id='differences' role='tabpanel'>
            $(if ($differCount -gt 0) { @"
            <div class='card'>
                <div class='card-body'>
                    <div class='table-responsive'>
                        <table class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th>Baseline Policy</th><th>Setting</th><th>Category</th><th>Description</th><th>Expected Value</th><th>Actual Value</th><th>Configured In</th>
                            </tr></thead>
                            <tbody>$differRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ } else { "<p class='text-muted'>No differences found.</p>" })
        </div>
        <div class='tab-pane fade' id='missing' role='tabpanel'>
            $(if ($missingCount -gt 0) { @"
            <div class='card'>
                <div class='card-body'>
                    <div class='table-responsive'>
                        <table class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th>Baseline Policy</th><th>Setting</th><th>Category</th><th>Description</th><th>Expected Value</th><th>Actual Value</th><th>Configured In</th>
                            </tr></thead>
                            <tbody>$missingRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ } else { "<p class='text-muted'>No missing settings.</p>" })
        </div>
        <div class='tab-pane fade' id='extra' role='tabpanel'>
            $(if ($extraSettings.Count -gt 0) { @"
            <div class='card'>
                <div class='card-body'>
                    <div class='table-responsive'>
                        <table class='table table-sm table-hover align-middle'>
                            <thead class='sticky-top'><tr>
                                <th>Policy</th><th>Setting</th><th>Category</th><th>Description</th><th>Configured Value</th>
                            </tr></thead>
                            <tbody>$extraRows</tbody>
                        </table>
                    </div>
                </div>
            </div>
"@ } else { "<p class='text-muted'>No extra settings found.</p>" })
        </div>
    </div>
    <div class='text-center small text-muted mt-4 mb-3'>Generated by Intune Toolkit • Baseline Comparison Report</div>
</div>
<button id='scrollTopBtn' class='scroll-top-btn btn btn-primary btn-sm'>Top</button>
<script>
function toggleDesc(btn){ const wrapper=btn.previousElementSibling; if(wrapper.classList.contains('expanded')){ wrapper.classList.remove('expanded'); wrapper.classList.add('clamp'); btn.textContent='More'; } else { wrapper.classList.remove('clamp'); wrapper.classList.add('expanded'); btn.textContent='Less'; } }
function handleScrollTopBtn(){ const btn=document.getElementById('scrollTopBtn'); if(!btn) return; btn.style.display= window.scrollY>300 ? 'block':'none'; } window.addEventListener('scroll',handleScrollTopBtn);
function filterTables(){ const searchEl=document.getElementById('blSearch'); const q=(searchEl ? searchEl.value : '').toLowerCase(); const tables=['matchTable','differTable','missingTable','extraTable']; tables.forEach(tid=>{ const tbl=document.getElementById(tid); if(!tbl) return; tbl.querySelectorAll('tbody tr').forEach(r=>{ const match=[...r.children].some(td=> td.textContent.toLowerCase().includes(q)); r.style.display = match ? '' : 'none'; }); }); }
document.addEventListener('input', e=>{ if(e.target && e.target.id==='blSearch'){ filterTables(); } });
document.addEventListener('DOMContentLoaded',()=>{ 
    handleScrollTopBtn(); 
    const t=document.getElementById('scrollTopBtn'); 
    if(t){ t.addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'})); } 
    // Handle card clicks and active states
    document.querySelectorAll('.card-clickable').forEach(card=>{ 
        card.addEventListener('shown.bs.tab', function(){ 
            document.querySelectorAll('.card-clickable').forEach(c=>c.classList.remove('active')); 
            this.classList.add('active'); 
        }); 
    }); 
    // Set initial active state
    document.querySelector('.card-clickable[data-bs-target="#all"]')?.classList.add('active');
});
</script>
<script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>
</body>
</html>
"@
                        $html | Out-File -FilePath $dlg.FileName -Encoding UTF8
                        Write-IntuneToolkitLog "HTML report saved to: $($dlg.FileName)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
                        try { Start-Process -FilePath $dlg.FileName } catch {}
                    }
                }
            }
        }
        
        [System.Windows.MessageBox]::Show("Baseline comparison report(s) saved successfully.", "Success")

    } catch {
        Write-IntuneToolkitLog "Error: $($_.Exception.Message)" -component "AdminTemplateBaselineComparison-Button" -file "AdminTemplateBaselineComparisonButton.ps1"
        [System.Windows.MessageBox]::Show("Failed to generate baseline comparison: $($_.Exception.Message)", "Error")
    }
})
