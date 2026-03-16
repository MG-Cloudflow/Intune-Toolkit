<#
.SYNOPSIS
Performs baseline comparison for Device Configuration policies.

.DESCRIPTION
When the Device Configuration Baseline Comparison button is clicked, this handler:
  - Validates policy selection
  - Fetches full Device Configuration policies from Graph API
  - Prompts user to select baseline folder
  - Loads baseline JSON files from DeviceConfiguration subfolder
  - Matches policies to baselines by @odata.type + displayName similarity
    (handles multiple baselines sharing the same @odata.type)
  - Recursively flattens nested objects to dot-path leaf properties
  - Filters out "not configured" defaults (null, false, 0, empty, deviceDefault, etc.)
  - Generates HTML/CSV/Markdown reports with Match/Differ/Missing/Extra status
  - Supports exporting multiple formats in a single pass
#>
$DeviceConfigBaselineButton.Add_Click({
    try {
        Write-IntuneToolkitLog "DeviceConfigBaselineButton clicked" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        #--------------------------------------------------------------------------------
        # Validate Selected Policies
        #--------------------------------------------------------------------------------
        if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
            Write-IntuneToolkitLog "No policies selected for baseline comparison." -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            [System.Windows.MessageBox]::Show("Please select one or more Device Configuration policies.", "Information")
            return
        }
        Write-IntuneToolkitLog "Selected policies count: $($PolicyDataGrid.SelectedItems.Count)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        # Deduplicate selected policies by ID
        $uniqueSelectedPolicies = $PolicyDataGrid.SelectedItems |
            Group-Object -Property PolicyId |
            ForEach-Object { $_.Group[0] }
        Write-IntuneToolkitLog "Unique policies count after deduplication: $($uniqueSelectedPolicies.Count)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        #--------------------------------------------------------------------------------
        # Fetch Full Policy Details from Graph API
        #--------------------------------------------------------------------------------
        $tenantPolicies = @()
        foreach ($policy in $uniqueSelectedPolicies) {
            $policyId = if ($policy.PSObject.Properties["PolicyId"]) { $policy.PolicyId } else { $policy.id }
            Write-IntuneToolkitLog "Fetching details for policy: $policyId" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            
            $policyUrl = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policyId)"
            try {
                $policyDetail = Invoke-MgGraphRequest -Uri $policyUrl -Method GET
                $tenantPolicies += $policyDetail
                Write-IntuneToolkitLog "Policy details retrieved for $policyId - Type: $($policyDetail.'@odata.type')" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            } catch {
                Write-IntuneToolkitLog "Error fetching policy $policyId : $($_.Exception.Message)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                continue
            }
        }

        if ($tenantPolicies.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Could not retrieve any policy details.", "Error")
            return
        }

        #--------------------------------------------------------------------------------
        # Locate Baseline Root Folder
        #--------------------------------------------------------------------------------
        $baselineRootPath = ".\SupportFiles\Intune Baselines"
        if (-not (Test-Path $baselineRootPath)) {
            Write-IntuneToolkitLog "Baseline folder not found at $baselineRootPath" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            [System.Windows.MessageBox]::Show("Baseline folder not found at: $baselineRootPath", "Error")
            return
        }
        Write-IntuneToolkitLog "Baseline root path found: $baselineRootPath" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        #--------------------------------------------------------------------------------
        # Get Available Baseline Folders
        #--------------------------------------------------------------------------------
        $baselineFolders = Get-ChildItem -Path $baselineRootPath -Directory
        if ($baselineFolders.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No baseline folders found in $baselineRootPath", "Error")
            return
        }
        Write-IntuneToolkitLog "Found $($baselineFolders.Count) baseline folder(s)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        #--------------------------------------------------------------------------------
        # Prompt User to Select Baseline Folder
        #--------------------------------------------------------------------------------
        $selectedBaselineNames = Show-BaselineSelectionDialog -Items ($baselineFolders | ForEach-Object { $_.Name })
        if (-not $selectedBaselineNames) {
            Write-IntuneToolkitLog "User cancelled baseline folder selection" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            return
        }
        $selectedBaselineFolders = $baselineFolders | Where-Object { $selectedBaselineNames -contains $_.Name }
        Write-IntuneToolkitLog "User selected baseline(s): $($selectedBaselineNames -join ', ')" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        # For Device Configuration, process only the first selected folder
        $selectedFolder = $selectedBaselineFolders[0]
        Write-IntuneToolkitLog "Processing baseline folder: $($selectedFolder.Name)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        $baselineFolderPath = $selectedFolder.FullName
        $deviceConfigPath = Join-Path $baselineFolderPath "DeviceConfiguration"
        
        if (-not (Test-Path $deviceConfigPath)) {
            [System.Windows.MessageBox]::Show("DeviceConfiguration subfolder not found in selected baseline:`n$deviceConfigPath", "Error")
            return
        }

        #--------------------------------------------------------------------------------
        # Load Baseline JSON Files
        #--------------------------------------------------------------------------------
        $baselineFiles = Get-ChildItem -Path $deviceConfigPath -Filter "*.json"
        if ($baselineFiles.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No baseline JSON files found in:`n$deviceConfigPath", "Error")
            return
        }
        Write-IntuneToolkitLog "Found $($baselineFiles.Count) baseline file(s)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        $baselinePolicies = @()
        foreach ($file in $baselineFiles) {
            try {
                $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                $baselinePolicies += $content
                Write-IntuneToolkitLog "Loaded baseline: $($file.Name) - Type: $($content.'@odata.type')" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            } catch {
                Write-IntuneToolkitLog "Error loading baseline file $($file.Name): $($_.Exception.Message)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            }
        }

        if ($baselinePolicies.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Could not load any baseline policies.", "Error")
            return
        }

        #--------------------------------------------------------------------------------
        # Prompt User to Select Which Baseline Policies to Use
        #--------------------------------------------------------------------------------
        # Group baselines by @odata.type to show user what's available
        $baselinesByType = $baselinePolicies | Group-Object -Property '@odata.type'
        
        Write-IntuneToolkitLog "Found baseline policies of $($baselinesByType.Count) different type(s)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
        
        # If there are multiple baselines of the same type, let user select which ones to use
        $baselinePolicyNames = $baselinePolicies | ForEach-Object { $_.displayName } | Sort-Object -Unique
        if ($baselinePolicyNames.Count -gt 1) {
            $selectedBaselinePolicyNames = Show-BaselineSelectionDialog -Items $baselinePolicyNames -Title "Select Baseline Policies to Compare" -Height 500 -Width 600
            if (-not $selectedBaselinePolicyNames) {
                Write-IntuneToolkitLog "User cancelled baseline policy selection" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                return
            }
            $baselinePolicies = $baselinePolicies | Where-Object { $selectedBaselinePolicyNames -contains $_.displayName }
            Write-IntuneToolkitLog "User selected baseline policies: $($selectedBaselinePolicyNames -join ', ')" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
        }

        #--------------------------------------------------------------------------------
        # Match Tenant Policies to Baselines and Compare
        # Uses shared Flatten-ForBaselineComparison and Test-IsNotConfiguredValue from Functions.ps1
        #--------------------------------------------------------------------------------
        $comparisonResults = @()

        foreach ($tenantPolicy in $tenantPolicies) {
            $tenantType = if ($tenantPolicy -is [hashtable]) { $tenantPolicy['@odata.type'] } else { $tenantPolicy.'@odata.type' }
            $tenantName = if ($tenantPolicy -is [hashtable]) { $tenantPolicy['displayName'] } else { $tenantPolicy.displayName }

            # Step 1: Find baselines with matching @odata.type
            $typeMatches = @($baselinePolicies | Where-Object {
                $bType = if ($_ -is [hashtable]) { $_['@odata.type'] } else { $_.'@odata.type' }
                $bType -eq $tenantType
            })

            if ($typeMatches.Count -eq 0) {
                Write-IntuneToolkitLog "No baseline found for type: $tenantType (policy: $tenantName)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                continue
            }

            # Step 2: Resolve best matching baseline when multiple share the same @odata.type
            $matchingBaseline = $null
            if ($typeMatches.Count -eq 1) {
                $matchingBaseline = $typeMatches[0]
            } else {
                # Score each candidate by displayName token overlap with tenant policy name
                $tenantTokens = @(($tenantName -split '[-_\s]+') | ForEach-Object { $_.ToLower().Trim() } | Where-Object { $_.Length -gt 1 })
                $scored = foreach ($candidate in $typeMatches) {
                    $candidateName = if ($candidate -is [hashtable]) { $candidate['displayName'] } else { $candidate.displayName }
                    $candidateTokens = @(($candidateName -split '[-_\s]+') | ForEach-Object { $_.ToLower().Trim() } | Where-Object { $_.Length -gt 1 })
                    $overlap = @($tenantTokens | Where-Object { $_ -in $candidateTokens }).Count
                    [PSCustomObject]@{ Baseline = $candidate; Name = $candidateName; Score = $overlap }
                }
                $scored = @($scored | Sort-Object -Property Score -Descending)

                # If top score is clearly better than second, use it automatically
                if ($scored.Count -ge 2 -and $scored[0].Score -gt $scored[1].Score -and $scored[0].Score -gt 0) {
                    $matchingBaseline = $scored[0].Baseline
                    Write-IntuneToolkitLog "Auto-matched '$tenantName' to baseline '$($scored[0].Name)' (score: $($scored[0].Score))" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                } else {
                    # Ambiguous match - show selection dialog for user to pick
                    $candidateNames = $typeMatches | ForEach-Object {
                        if ($_ -is [hashtable]) { $_['displayName'] } else { $_.displayName }
                    }
                    Write-IntuneToolkitLog "Multiple baselines match type $tenantType for '$tenantName'. Prompting user." -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                    $selectedName = Show-BaselineSelectionDialog -Items $candidateNames -Title "Select baseline for: $tenantName" -Height 350 -Width 500
                    if (-not $selectedName) {
                        Write-IntuneToolkitLog "User skipped baseline selection for '$tenantName'" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                        continue
                    }
                    $matchingBaseline = $typeMatches | Where-Object {
                        $bName = if ($_ -is [hashtable]) { $_['displayName'] } else { $_.displayName }
                        $bName -eq $selectedName[0]
                    } | Select-Object -First 1
                }
            }

            if (-not $matchingBaseline) {
                Write-IntuneToolkitLog "No baseline match resolved for '$tenantName'" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                continue
            }

            $baselineName = if ($matchingBaseline -is [hashtable]) { $matchingBaseline['displayName'] } else { $matchingBaseline.displayName }
            Write-IntuneToolkitLog "Comparing '$tenantName' against baseline '$baselineName'" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

            # Step 3: Flatten both policies to dot-path property hashtables (leaf values only)
            $flatBaseline = Flatten-ForBaselineComparison -Policy $matchingBaseline
            $flatTenant = Flatten-ForBaselineComparison -Policy $tenantPolicy

            # Step 4: Get union of all property paths, sorted for consistent output
            $allProperties = @(@($flatBaseline.Keys) + @($flatTenant.Keys) | Select-Object -Unique | Sort-Object)

            # Determine config type from @odata.type
            $configType = if ($tenantType -match '#microsoft\.graph\.(.+)$') { $Matches[1] } else { "Unknown" }

            # Step 5: Compare each property
            foreach ($propPath in $allProperties) {
                $baselineValue = $flatBaseline[$propPath]
                $tenantValue = $flatTenant[$propPath]

                # Skip when both sides are "not configured" (null, false, 0, empty, deviceDefault, etc.)
                $baselineNotConfigured = Test-IsNotConfiguredValue -Value $baselineValue
                $tenantNotConfigured = Test-IsNotConfiguredValue -Value $tenantValue

                if ($baselineNotConfigured -and $tenantNotConfigured) {
                    continue
                }

                # Determine comparison status using KEY presence for Missing/Extra,
                # VALUE comparison for Match/Differs.
                # Missing = property path only exists in baseline (not in tenant at all)
                # Extra   = property path only exists in tenant (not in baseline at all)
                # Differs = both sides have the property but values are different
                $baselineHasKey = $flatBaseline.ContainsKey($propPath)
                $tenantHasKey = $flatTenant.ContainsKey($propPath)

                $status = "Match"
                if (-not $baselineHasKey) {
                    $status = "Extra"
                }
                elseif (-not $tenantHasKey) {
                    $status = "Missing"
                }
                else {
                    # Both sides have the property - compare actual values
                    if ($baselineValue -is [System.Array] -and $tenantValue -is [System.Array]) {
                        $diff = Compare-Object -ReferenceObject @($baselineValue | Sort-Object) -DifferenceObject @($tenantValue | Sort-Object) -ErrorAction SilentlyContinue
                        $status = if ($diff) { "Differs" } else { "Match" }
                    }
                    elseif ("$baselineValue" -eq "$tenantValue") {
                        $status = "Match"
                    }
                    else {
                        $status = "Differs"
                    }
                }

                # Format array values for display
                $displayBaseline = if ($baselineValue -is [System.Array]) { $baselineValue -join ", " } else { $baselineValue }
                $displayTenant = if ($tenantValue -is [System.Array]) { $tenantValue -join ", " } else { $tenantValue }

                $comparisonResults += [PSCustomObject]@{
                    BaselinePolicy  = $baselineName
                    TenantPolicy    = $tenantName
                    PropertyPath    = $propPath
                    BaselineValue   = $displayBaseline
                    TenantValue     = $displayTenant
                    Status          = $status
                    ConfigType      = $configType
                }
            }
        }

        if ($comparisonResults.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No comparison results generated. Check that tenant policies match baseline types.", "No Results")
            return
        }

        #--------------------------------------------------------------------------------
        # Generate Summary Statistics
        #--------------------------------------------------------------------------------
        $totalCount = $comparisonResults.Count
        $matchCount = ($comparisonResults | Where-Object { $_.Status -eq "Match" }).Count
        $differCount = ($comparisonResults | Where-Object { $_.Status -eq "Differs" }).Count
        $missingCount = ($comparisonResults | Where-Object { $_.Status -eq "Missing" }).Count
        $extraCount = ($comparisonResults | Where-Object { $_.Status -eq "Extra" }).Count

        Write-IntuneToolkitLog "Comparison results - Total: $totalCount, Matches: $matchCount, Differs: $differCount, Missing: $missingCount, Extra: $extraCount" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"

        #--------------------------------------------------------------------------------
        # Prompt User for Export Format
        #--------------------------------------------------------------------------------
        $exportChoice = Show-ExportOptionsDialog
        if (-not $exportChoice) {
            Write-IntuneToolkitLog "User cancelled export" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
            return
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $baseName = "DeviceConfigBaseline_$($selectedFolder.Name)_$timestamp"

        foreach ($format in $exportChoice) {

        #--------------------------------------------------------------------------------
        # MARKDOWN EXPORT
        #--------------------------------------------------------------------------------
        if ($format -eq "Markdown") {
            $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $saveFileDialog.Filter = "Markdown files (*.md)|*.md"
            $saveFileDialog.FileName = "$baseName.md"
            if ($saveFileDialog.ShowDialog()) {
                $mdLines = @()
                $mdLines += "# Device Configuration Baseline Comparison"
                $mdLines += ""
                $mdLines += "**Baseline Folder:** $($selectedFolder.Name)"
                $mdLines += "**Tenant Policies Compared:** $($tenantPolicies.Count)"
                $mdLines += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $mdLines += ""
                $mdLines += "*Note: Only configured settings are compared. Not configured properties are excluded.*"
                $mdLines += ""
                $mdLines += "## Summary"
                $mdLines += "- Total Configured Settings: $totalCount"
                $mdLines += "- Matches: $matchCount"
                $mdLines += "- Differences: $differCount"
                $mdLines += "- Missing: $missingCount"
                $mdLines += "- Extra: $extraCount"
                $mdLines += ""
                
                # Matches
                if ($matchCount -gt 0) {
                    $mdLines += "## ✓ Matching Settings ($matchCount)"
                    $mdLines += ""
                    $mdLines += "| Baseline | Tenant Policy | Property Path | Value |"
                    $mdLines += "|----------|---------------|---------------|-------|"
                    $matches = $comparisonResults | Where-Object { $_.Status -eq "Match" }
                    foreach ($match in $matches) {
                        $mdLines += "| $($match.BaselinePolicy) | $($match.TenantPolicy) | $($match.PropertyPath) | $($match.BaselineValue) |"
                    }
                    $mdLines += ""
                }
                
                # Differences
                if ($differCount -gt 0) {
                    $mdLines += "## ✗ Different Settings ($differCount)"
                    $mdLines += ""
                    $mdLines += "| Baseline | Tenant Policy | Property Path | Expected Value | Actual Value |"
                    $mdLines += "|----------|---------------|---------------|----------------|--------------|"
                    $differs = $comparisonResults | Where-Object { $_.Status -eq "Differs" }
                    foreach ($diff in $differs) {
                        $mdLines += "| $($diff.BaselinePolicy) | $($diff.TenantPolicy) | $($diff.PropertyPath) | $($diff.BaselineValue) | $($diff.TenantValue) |"
                    }
                    $mdLines += ""
                }
                
                # Missing
                if ($missingCount -gt 0) {
                    $mdLines += "## ⚠ Missing Settings ($missingCount)"
                    $mdLines += ""
                    $mdLines += "| Baseline | Tenant Policy | Property Path | Expected Value |"
                    $mdLines += "|----------|---------------|---------------|----------------|"
                    $missing = $comparisonResults | Where-Object { $_.Status -eq "Missing" }
                    foreach ($miss in $missing) {
                        $mdLines += "| $($miss.BaselinePolicy) | $($miss.TenantPolicy) | $($miss.PropertyPath) | $($miss.BaselineValue) |"
                    }
                    $mdLines += ""
                }
                
                # Extra
                if ($extraCount -gt 0) {
                    $mdLines += "## + Extra Settings ($extraCount)"
                    $mdLines += ""
                    $mdLines += "| Tenant Policy | Property Path | Actual Value |"
                    $mdLines += "|---------------|---------------|--------------|"
                    $extras = $comparisonResults | Where-Object { $_.Status -eq "Extra" }
                    foreach ($extra in $extras) {
                        $mdLines += "| $($extra.TenantPolicy) | $($extra.PropertyPath) | $($extra.TenantValue) |"
                    }
                }
                
                $mdContent = $mdLines -join "`r`n"
                Set-Content -Path $saveFileDialog.FileName -Value $mdContent -Encoding UTF8
                Write-IntuneToolkitLog "Markdown report saved: $($saveFileDialog.FileName)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                [System.Windows.MessageBox]::Show("Markdown report saved to:`n$($saveFileDialog.FileName)", "Success")
            }
        }

        #--------------------------------------------------------------------------------
        # CSV EXPORT
        #--------------------------------------------------------------------------------
        if ($format -eq "CSV") {
            $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $saveFileDialog.Filter = "CSV files (*.csv)|*.csv"
            $saveFileDialog.FileName = "$baseName.csv"
            if ($saveFileDialog.ShowDialog()) {
                $csvData = $comparisonResults | Select-Object BaselinePolicy, TenantPolicy, PropertyPath, BaselineValue, TenantValue, Status, ConfigType
                $csvData | Export-Csv -Path $saveFileDialog.FileName -Delimiter ';' -NoTypeInformation -Encoding UTF8
                Write-IntuneToolkitLog "CSV report saved: $($saveFileDialog.FileName)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                [System.Windows.MessageBox]::Show("CSV report saved to:`n$($saveFileDialog.FileName)", "Success")
            }
        }

        #--------------------------------------------------------------------------------
        # HTML EXPORT
        #--------------------------------------------------------------------------------
        if ($format -eq "HTML") {
            try {
                Add-Type -AssemblyName System.Web
            } catch {}
            
            # Build HTML table rows
            $matchRows = ""
            $differRows = ""
            $missingRows = ""
            $extraRows = ""
            
            foreach ($result in $comparisonResults) {
                $baselineEsc = [System.Web.HttpUtility]::HtmlEncode($result.BaselinePolicy)
                $tenantEsc = [System.Web.HttpUtility]::HtmlEncode($result.TenantPolicy)
                $propEsc = [System.Web.HttpUtility]::HtmlEncode($result.PropertyPath)
                $baseValEsc = [System.Web.HttpUtility]::HtmlEncode($result.BaselineValue)
                $tenantValEsc = [System.Web.HttpUtility]::HtmlEncode($result.TenantValue)
                $configTypeEsc = [System.Web.HttpUtility]::HtmlEncode($result.ConfigType)
                
                $row = "<tr data-status='$($result.Status)' data-configtype='$configTypeEsc'><td>$baselineEsc</td><td>$tenantEsc</td><td>$propEsc</td><td>$baseValEsc</td><td>$tenantValEsc</td><td>$configTypeEsc</td></tr>"
                
                switch ($result.Status) {
                    "Match" { $matchRows += $row }
                    "Differs" { $differRows += $row }
                    "Missing" { $missingRows += $row }
                    "Extra" { $extraRows += $row }
                }
            }
            
            # Get unique config types
            $configTypes = $comparisonResults | Select-Object -ExpandProperty ConfigType -Unique | Sort-Object
            $configTypeFilterOptions = ($configTypes | ForEach-Object { 
                $typeEsc = [System.Web.HttpUtility]::HtmlEncode($_)
                $idSafe = ($typeEsc -replace "[^a-zA-Z0-9_-]","_")
                "<div class='form-check form-check-sm'><input class='form-check-input configtype-filter-cb' type='checkbox' value='$typeEsc' id='type_$idSafe' checked><label class='form-check-label small' for='type_$idSafe'>$typeEsc</label></div>"
            }) -join "`n"
            
            # Icon (optional)
            $iconBase64 = ''
            $headerLogoBase64 = ''
            $headerLogoMime = 'image/png'
            $iconPathIco = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.ico'
            if (Test-Path $iconPathIco) { $bytesIco = [System.IO.File]::ReadAllBytes($iconPathIco); $iconBase64 = [Convert]::ToBase64String($bytesIco) }
            $logoPathPng = Join-Path -Path (Get-Location) -ChildPath 'Intune-toolkit.png'
            if (Test-Path $logoPathPng) { $logoBytes = [System.IO.File]::ReadAllBytes($logoPathPng); $headerLogoBase64 = [Convert]::ToBase64String($logoBytes) } elseif ($iconBase64) { $headerLogoBase64 = $iconBase64; $headerLogoMime='image/x-icon' }
            $iconImg = if ($headerLogoBase64) { "<img src='data:$headerLogoMime;base64,$headerLogoBase64' class='header-logo' alt='Intune Toolkit Logo'>" } else { '' }

            $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $tenant = try { (Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/organization' -Method GET).value[0].displayName } catch { 'Unknown Tenant' }
            
            function _pct($n,$d){ if($d){ [math]::Round(($n/$d)*100,1) } else { 0 } }
            $matchPct = _pct $matchCount $totalCount
            $differPct = _pct $differCount $totalCount
            $missingPct = _pct $missingCount $totalCount
            
            $htmlContent = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'/>
<title>Device Configuration Baseline Comparison</title>
<meta name='viewport' content='width=device-width,initial-scale=1'/>
<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css' rel='stylesheet'/>
<link rel='icon' type='image/x-icon' href='data:image/x-icon;base64,$iconBase64'>
<style>
:root { --primary:#007ACC; --primary-dark:#005A9E; --muted:#888888; }
body{padding:24px;background:#f5f7fa;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;}
.header-logo{width:64px;height:64px;border-radius:12px;box-shadow:0 3px 8px rgba(0,0,0,.18);background:#fff;padding:6px;object-fit:contain;}
.header-bar{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;border-radius:12px;padding:18px 24px;box-shadow:0 4px 12px rgba(0,0,0,.15);}
table{font-size:.9rem;}
thead.sticky-top th{background:linear-gradient(135deg,var(--primary-dark),var(--primary));color:#fff;white-space:nowrap;position:sticky;top:0;z-index:20;}
.summary-badge{font-size:.75rem;padding:.45em .65em;border-radius:8px;font-weight:600;}
.badge-match{background:#198754;color:#fff;}
.badge-diff{background:#ffc107;color:#212529;}
.badge-missing{background:#fd7e14;color:#fff;}
.badge-extra{background:#0dcaf0;color:#212529;}
.search-box{max-width:340px;}
.card{border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,.08);}
.summary-card{cursor:pointer;transition:all .2s;}
.summary-card:hover{transform:translateY(-3px);box-shadow:0 4px 12px rgba(0,0,0,.15);}
.summary-card.active{border:3px solid var(--primary);box-shadow:0 0 0 3px rgba(0,122,204,.25);}
thead th{position:relative;}
.col-resizer{position:absolute;top:0;right:0;width:6px;cursor:col-resize;user-select:none;height:100%;}
html.resizing, html.resizing * {cursor:col-resize !important;}
table.comparisonTable { table-layout:auto; }
.comparisonTable th,.comparisonTable td{word-break:break-word;vertical-align:top;}
.offcanvas-filters{width:320px;}
.filter-active-indicator{width:10px;height:10px;border-radius:50%;background:#198754;display:inline-block;margin-left:6px;box-shadow:0 0 0 3px rgba(25,135,84,.25);}
.scroll-top-btn{position:fixed;bottom:24px;right:24px;display:none;z-index:999;box-shadow:0 3px 10px rgba(0,0,0,.25);}
.tab-pane{min-height:200px;}
</style>
</head>
<body>
<div class='container-fluid'>
    <div class='header-bar mb-4 d-flex flex-wrap justify-content-between align-items-center gap-4'>
    <div class='d-flex align-items-center gap-3'>$iconImg<div><h1 class='h4 mb-1'>Device Configuration Baseline Comparison</h1><div class='small opacity-75'>Tenant: $tenant | Baseline: $($selectedFolder.Name) | Generated: $generated</div><div class='small opacity-75'>Policies: $($tenantPolicies.Count)</div></div></div>
    <div class='search-box'><input id='blSearch' class='form-control form-control-sm' placeholder='Search report...'></div>
    </div>
    <div class='row g-3 mb-4 align-items-stretch'>
        <div class='col-12 col-md-6 col-xl-2'>
            <div class='card h-100 summary-card' data-bs-toggle='pill' data-bs-target='#all'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Total Configured</h6><div class='h4 mb-0'><span id='totalConfiguredCount'>$totalCount</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2'>
            <div class='card h-100 summary-card' data-bs-toggle='pill' data-bs-target='#matches'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Matches</h6><div class='h4 mb-0'><span id='matchesCount'>$matchCount</span> <span class='summary-badge badge-match ms-1'><span id='matchesPct'>$matchPct</span>%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2'>
            <div class='card h-100 summary-card' data-bs-toggle='pill' data-bs-target='#differences'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Differences</h6><div class='h4 mb-0'><span id='differencesCount'>$differCount</span> <span class='summary-badge badge-diff ms-1'><span id='differencesPct'>$differPct</span>%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2'>
            <div class='card h-100 summary-card' data-bs-toggle='pill' data-bs-target='#missing'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Missing</h6><div class='h4 mb-0'><span id='missingCount'>$missingCount</span> <span class='summary-badge badge-missing ms-1'><span id='missingPct'>$missingPct</span>%</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2'>
            <div class='card h-100 summary-card' data-bs-toggle='pill' data-bs-target='#extra'><div class='card-body'><h6 class='text-uppercase small text-muted mb-2'>Extra</h6><div class='h4 mb-0'><span id='extraCount'>$extraCount</span></div></div></div>
        </div>
        <div class='col-12 col-md-6 col-xl-2 d-flex'>
            <div class='card h-100 w-100' data-bs-toggle='offcanvas' data-bs-target='#offcanvasFilters' aria-controls='offcanvasFilters' style='cursor:pointer;'>
                <div class='card-body d-flex flex-column justify-content-center'>
                    <h6 class='text-uppercase small text-muted mb-2'>Filters</h6>
                    <div class='h6 mb-0'>Config Type <span id='activeFilterDot' style='display:none;' class='filter-active-indicator'></span></div>
                    <div class='small text-muted mt-1'>Click to refine</div>
                </div>
            </div>
        </div>
    </div>

<div class='tab-content' id='comparisonTabs'>
<div class='tab-pane fade show active' id='all' role='tabpanel'>
$(if ($matchCount -gt 0) { @"
<div class='card mb-4'><div class='card-body'><h2 class='h5 text-success mb-3'>✓ Matching Settings ($matchCount)</h2><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$matchRows</tbody></table></div></div></div>
"@ })
$(if ($differCount -gt 0) { @"
<div class='card mb-4'><div class='card-body'><h2 class='h5 text-danger mb-3'>✗ Different Settings ($differCount)</h2><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$differRows</tbody></table></div></div></div>
"@ })
$(if ($missingCount -gt 0) { @"
<div class='card mb-4'><div class='card-body'><h2 class='h5 text-warning mb-3'>⚠ Missing Settings ($missingCount)</h2><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$missingRows</tbody></table></div></div></div>
"@ })
$(if ($extraCount -gt 0) { @"
<div class='card mb-4'><div class='card-body'><h2 class='h5 text-primary mb-3'>+ Extra Settings ($extraCount)</h2><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$extraRows</tbody></table></div></div></div>
"@ })
</div>
<div class='tab-pane fade' id='matches' role='tabpanel'>
$(if ($matchCount -gt 0) { "<div class='card'><div class='card-body'><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$matchRows</tbody></table></div></div></div>" } else { "<p class='text-muted'>No matching settings found.</p>" })
</div>
<div class='tab-pane fade' id='differences' role='tabpanel'>
$(if ($differCount -gt 0) { "<div class='card'><div class='card-body'><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$differRows</tbody></table></div></div></div>" } else { "<p class='text-muted'>No differences found.</p>" })
</div>
<div class='tab-pane fade' id='missing' role='tabpanel'>
$(if ($missingCount -gt 0) { "<div class='card'><div class='card-body'><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$missingRows</tbody></table></div></div></div>" } else { "<p class='text-muted'>No missing settings found.</p>" })
</div>
<div class='tab-pane fade' id='extra' role='tabpanel'>
$(if ($extraCount -gt 0) { "<div class='card'><div class='card-body'><div class='table-responsive'><table class='comparisonTable table table-sm table-hover align-middle'><thead class='sticky-top'><tr><th>Baseline</th><th>Tenant Policy</th><th>Property Path</th><th>Expected Value</th><th>Actual Value</th><th>Config Type</th></tr></thead><tbody>$extraRows</tbody></table></div></div></div>" } else { "<p class='text-muted'>No extra settings found.</p>" })
</div>
</div>
</div>

    <div class='offcanvas offcanvas-end offcanvas-filters' tabindex='-1' id='offcanvasFilters' aria-labelledby='offcanvasFiltersLabel'>
        <div class='offcanvas-header'>
            <h5 class='offcanvas-title' id='offcanvasFiltersLabel'>Filter & Refine</h5>
            <button type='button' class='btn-close text-reset' data-bs-dismiss='offcanvas' aria-label='Close'></button>
        </div>
        <div class='offcanvas-body d-flex flex-column'>
            <div class='mb-3'>
                <h6 class='text-muted text-uppercase small mb-2'>Column Visibility</h6>
                <div id='columnVisibilityContainer' class='d-flex flex-wrap gap-2 mb-3'></div>
                <h6 class='text-muted text-uppercase small mb-2 mt-2'>Configuration Type</h6>
                <div class='overflow-auto border rounded p-2' style='max-height:200px' id='configTypeContainer'>$configTypeFilterOptions</div>
                <div class='mt-2 d-flex gap-2 flex-wrap'>
                    <button class='btn btn-sm btn-primary' type='button' onclick='applyConfigTypeFilters()'>Apply</button>
                    <button class='btn btn-sm btn-outline-secondary' type='button' onclick='clearConfigTypeFilters()'>Clear</button>
                    <button class='btn btn-sm btn-outline-primary' type='button' onclick='selectAllConfigTypeFilters()'>Select All</button>
                </div>
            </div>
        </div>
    </div>

<button id='scrollTopBtn' class='scroll-top-btn btn btn-primary btn-sm'>Top</button>
<script>
function makeColsResizable(tableClass){ document.querySelectorAll(tableClass+' thead th').forEach((th,idx)=>{ if(th.querySelector('.col-resizer')) return; th.style.position='relative'; const grip=document.createElement('span'); grip.className='col-resizer'; grip.title='Drag to resize'; th.appendChild(grip); let startX,startWidth; grip.addEventListener('mousedown',e=>{ startX=e.pageX; startWidth=th.offsetWidth; document.documentElement.classList.add('resizing'); function onMove(ev){ let w=startWidth+(ev.pageX-startX); if(w<60) w=60; th.style.width=w+'px'; } function onUp(){ document.removeEventListener('mousemove',onMove); document.removeEventListener('mouseup',onUp); document.documentElement.classList.remove('resizing'); } document.addEventListener('mousemove',onMove); document.addEventListener('mouseup',onUp); e.preventDefault(); e.stopPropagation(); }); }); }
function handleScrollTopBtn(){ const btn=document.getElementById('scrollTopBtn'); if(!btn) return; btn.style.display= window.scrollY>300 ? 'block':'none'; } window.addEventListener('scroll',handleScrollTopBtn);
let currentSelectedConfigTypes=[];
function applyConfigTypeFilters(){ const cbs=document.querySelectorAll('.configtype-filter-cb'); currentSelectedConfigTypes=[...cbs].filter(cb=>cb.checked).map(cb=>cb.value.toLowerCase()); filterByConfigType(); const dot=document.getElementById('activeFilterDot'); if(dot){ dot.style.display=currentSelectedConfigTypes.length<cbs.length?'inline-block':'none'; } }
function filterByConfigType(){ const rows=document.querySelectorAll('.comparisonTable tbody tr'); rows.forEach(r=>{ if(currentSelectedConfigTypes.length===0){ r.dataset.configfiltered='0'; } else { const type=(r.getAttribute('data-configtype')||'').toLowerCase(); r.dataset.configfiltered= currentSelectedConfigTypes.includes(type)?'0':'1'; } }); applyCombinedVisibility(); }
function clearConfigTypeFilters(){ document.querySelectorAll('.configtype-filter-cb').forEach(cb=> cb.checked=false); currentSelectedConfigTypes=[]; filterByConfigType(); }
function selectAllConfigTypeFilters(){ document.querySelectorAll('.configtype-filter-cb').forEach(cb=> cb.checked=true); }
function filterBaselineTbl(){
    const searchEl = document.getElementById('blSearch');
    const q = (searchEl ? searchEl.value : '').toLowerCase();
    document.querySelectorAll('.comparisonTable tbody tr').forEach(r=>{
        const match=[...r.children].some(td=> td.textContent.toLowerCase().includes(q));
        r.dataset.searchHidden = match ? '0' : '1';
    });
    applyCombinedVisibility();
}
function applyCombinedVisibility(){
    const rows=document.querySelectorAll('.comparisonTable tbody tr');
    rows.forEach(r=>{
        let hide = (r.dataset.searchHidden==='1' || r.dataset.configfiltered==='1');
        r.style.display = hide ? 'none' : '';
    });
    updateSummaryStats();
}
function updateSummaryStats(){
    const allRows=[...document.querySelectorAll('.comparisonTable tbody tr')];
    const visibleRows=allRows.filter(r=> r.style.display!=='none');
    const statuses=visibleRows.map(r=>r.getAttribute('data-status'));
    const totalVisible=visibleRows.length;
    const matches=statuses.filter(s=>s==='Match').length;
    const differs=statuses.filter(s=>s==='Differs').length;
    const missing=statuses.filter(s=>s==='Missing').length;
    const extra=statuses.filter(s=>s==='Extra').length;
    const pct=(n)=> totalVisible? ((n/totalVisible)*100).toFixed(1).replace(/\\.0$/,''):'0';
    function setTxt(id,v){ const el=document.getElementById(id); if(el) el.textContent=v; }
    setTxt('totalConfiguredCount', totalVisible);
    setTxt('matchesCount', matches);
    setTxt('differencesCount', differs);
    setTxt('missingCount', missing);
    setTxt('extraCount', extra);
    setTxt('matchesPct', pct(matches));
    setTxt('differencesPct', pct(differs));
    setTxt('missingPct', pct(missing));
}
document.addEventListener('input', e=>{ if(e.target && e.target.id==='blSearch'){ filterBaselineTbl(); } });
document.addEventListener('change', e=>{
    if(e.target && e.target.classList.contains('configtype-filter-cb')){ applyConfigTypeFilters(); }
});
document.addEventListener('DOMContentLoaded',()=>{ makeColsResizable('.comparisonTable'); handleScrollTopBtn(); const t=document.getElementById('scrollTopBtn'); if(t){ t.addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'})); }
    const colContainer=document.getElementById('columnVisibilityContainer'); if(colContainer){ const headers=document.querySelectorAll('.comparisonTable thead th'); headers.forEach((h,idx)=>{ const label=h.textContent.trim(); const id='colvis_'+idx; const div=document.createElement('div'); div.className='form-check form-check-sm me-2'; div.innerHTML='<input class=\"form-check-input col-vis-cb\" type=\"checkbox\" id=\"'+id+'\" data-col=\"'+idx+'\" checked><label class=\"form-check-label small\" for=\"'+id+'\">'+label+'</label>'; colContainer.appendChild(div); }); colContainer.addEventListener('change', e=>{ const cb=e.target.closest('.col-vis-cb'); if(!cb) return; const col=cb.getAttribute('data-col'); document.querySelectorAll('.comparisonTable').forEach(table=>{ table.querySelectorAll('thead th:nth-child('+(parseInt(col)+1)+'), tbody td:nth-child('+(parseInt(col)+1)+')').forEach(cell=>{ cell.style.display = cb.checked? '' : 'none'; }); }); }); }
    document.querySelectorAll('.summary-card[data-bs-toggle=\"pill\"]').forEach(card=>{ card.addEventListener('click',()=>{ document.querySelectorAll('.summary-card').forEach(c=>c.classList.remove('active')); card.classList.add('active'); }); });
    document.querySelector('.summary-card').classList.add('active');
    document.querySelectorAll('.comparisonTable tbody tr').forEach(r=>{ r.dataset.searchHidden='0'; r.dataset.configfiltered='0'; });
    filterBaselineTbl();
    updateSummaryStats();
});
</script>
<script src='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js'></script>
</body>
</html>
"@
            
            $saveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $saveFileDialog.Filter = "HTML files (*.html)|*.html"
            $saveFileDialog.FileName = "$baseName.html"
            if ($saveFileDialog.ShowDialog()) {
                Set-Content -Path $saveFileDialog.FileName -Value $htmlContent -Encoding UTF8
                Write-IntuneToolkitLog "HTML report saved: $($saveFileDialog.FileName)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
                [System.Windows.MessageBox]::Show("HTML report saved to:`n$($saveFileDialog.FileName)`n`nOpening in browser...", "Success")
                Start-Process $saveFileDialog.FileName
            }
        }

        } # end foreach export format

    } catch {
        Write-IntuneToolkitLog "Error in DeviceConfigBaselineButton: $($_.Exception.Message)" -component "DeviceConfigBaselineComparison-Button" -file "DeviceConfigurationBaselineButton.ps1"
        [System.Windows.MessageBox]::Show("An error occurred: $($_.Exception.Message)", "Error")
    }
})
