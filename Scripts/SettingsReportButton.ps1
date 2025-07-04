<#
.SYNOPSIS
Exports a settings-only report for selected Intune configuration policies with debug logging.
.DESCRIPTION
When the Settings Report button is clicked, this handler:
  - Validates policy selection
  - Deduplicates selected policies by ID
  - Retrieves raw settings for each unique policy
  - Flattens settings via existing Flatten-PolicySettings function
  - Outputs debug logs capturing flattened entries
  - Builds a Markdown or CSV report listing each setting’s friendly name, description, configured value, and the policy it belongs to
#>
$SettingsReportButton.Add_Click({
    try {
        Write-IntuneToolkitLog "SettingsReportButton clicked" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Validate UI selection
        if (-not $PolicyDataGrid.SelectedItems -or $PolicyDataGrid.SelectedItems.Count -eq 0) {
            Write-IntuneToolkitLog "No policies selected." -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            [System.Windows.MessageBox]::Show("Select one or more configuration policies.", "Information")
            return
        }

        # Deduplicate selected policies by ID
        $uniquePolicies = $PolicyDataGrid.SelectedItems |
            Group-Object -Property { if ($_.PSObject.Properties['PolicyId']) { $_.PolicyId } else { $_.id } } |
            ForEach-Object { $_.Group[0] }
        Write-IntuneToolkitLog "Unique policies count: $($uniquePolicies.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Fetch & merge raw settings
        $mergedSettings = @()
        foreach ($policy in $uniquePolicies) {
            $policyId   = if ($policy.PSObject.Properties['PolicyId']) { $policy.PolicyId } else { $policy.id }
            Write-IntuneToolkitLog "Fetching details for policy: $($policyId)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            $url = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policyId)?`$expand=settings"
            try {
                $detail = Invoke-MgGraphRequest -Uri $url -Method GET
            } catch {
                Write-IntuneToolkitLog "Error fetching policy $($policyId): $($_.Exception.Message)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
                continue
            }
            if ($detail.settings) {
                $settingsArray = if ($detail.settings -is [System.Array]) { $detail.settings } else { @($detail.settings) }
                Write-IntuneToolkitLog "Policy '$($detail.name)' returned $($settingsArray.Count) settings" -component "SettingsReport-Debug" -file "SettingsReportHandler.ps1"
                foreach ($s in $settingsArray) {
                    if (-not ($s.settingDefinitionId -or ($s.settingInstance -and $s.settingInstance.settingDefinitionId))) {
                        Write-IntuneToolkitLog "Skipping entry without DefinitionId" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
                        continue
                    }
                    $mergedSettings += [PSCustomObject]@{
                        PolicyName = $detail.name
                        Setting    = $s
                    }
                }
            } else {
                Write-IntuneToolkitLog "Policy $($detail.name) has no settings to merge." -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            }
        }
        Write-IntuneToolkitLog "Total merged settings: $($mergedSettings.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        if ($mergedSettings.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No configurable settings found.", "Information")
            return
        }

        # Flatten settings
        $flattened = Flatten-PolicySettings -MergedPolicy $mergedSettings
        Write-IntuneToolkitLog "Flattened entries count: $($flattened.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Ensure catalog
        $catalogPath = ".\SupportFiles\SettingsCatalog.json"
        if (-not (Test-Path $catalogPath)) {
            Write-IntuneToolkitLog "Missing catalog at $($catalogPath)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
            [System.Windows.MessageBox]::Show("Settings catalog not found.", "Error")
            return
        }
        $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json
        $CatalogDictionary = Build-CatalogDictionary -Catalog $catalog

        # Group by setting ID to combine duplicates
        $grouped = $flattened | Group-Object -Property PolicySettingId

        # Prepare report items
        $reportItems = @()
        foreach ($group in $grouped) {
            $id           = $group.Name
            $policiesList = ($group.Group | ForEach-Object { $_.PolicyName }) -join "; "
            $dispName     = (Get-SettingDisplayValue -settingValueId $id -CatalogDictionary $CatalogDictionary) || $id
            $desc         = Get-SettingDescription   -settingId       $id -CatalogDictionary $CatalogDictionary
            $uniqueVals   = ($group.Group | ForEach-Object { $_.ActualValue }) | Select-Object -Unique
            $dispVals     = foreach ($val in $uniqueVals) {
                if ($val) { (Get-SettingDisplayValue -settingValueId $val -CatalogDictionary $CatalogDictionary) || $val }
            }
            $valueDisplay = $dispVals -join "; "
            $reportItems += [PSCustomObject]@{
                PolicyName      = $policiesList
                Setting         = $dispName
                Description     = $desc
                ConfiguredValue = $valueDisplay
            }
        }
        Write-IntuneToolkitLog "Report items prepared: $($reportItems.Count)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"

        # Show export options
        $formats  = Show-ExportOptionsDialog
        if (-not $formats -or $formats.Count -eq 0) { return }
        Add-Type -AssemblyName System.Windows.Forms
        $baseName = "SettingsReport_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"

        foreach ($fmt in $formats) {
            switch ($fmt) {
                'Markdown' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'Markdown (*.md)|*.md|All (*.*)|*.*'
                    $dlg.Title    = 'Save Settings Report'
                    $dlg.FileName = "$baseName.md"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        # Overview of shared settings
                        $overview = foreach ($g in $grouped | Where-Object { $_.Count -gt 1 }) {
                            $name = (Get-SettingDisplayValue -settingValueId $g.Name -CatalogDictionary $CatalogDictionary) || $g.Name
                            $pols = ($g.Group | ForEach-Object { $_.PolicyName }) -join "; "
                            "- **$name** configured in policies: $pols"
                        }
                        $md = @('# Settings Report', '', '## Overview: Shared Settings', '')
                        if ($overview) { $md += $overview } else { $md += '- No settings shared across multiple policies.' }
                        $md += @('', '| Policy Name | Setting | Description | Value |', '|-------------|---------|-------------|-------|')
                        foreach ($r in $reportItems) {
                            $md += "| $($r.PolicyName) | $($r.Setting) | $($r.Description) | $($r.ConfiguredValue) |"
                        }
                        $md -join "`r`n" | Out-File -FilePath $dlg.FileName -Encoding UTF8
                    }
                }
                'CSV' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'CSV (*.csv)|*.csv|All (*.*)|*.*'
                    $dlg.Title    = 'Save Settings Report CSV'
                    $dlg.FileName = "$baseName.csv"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $reportItems | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
                    }
                }
            }
        }

        [System.Windows.MessageBox]::Show("Export complete.", "Success")
    } catch {
        Write-IntuneToolkitLog "Error: $($_.Exception.Message)" -component "SettingsReport-Button" -file "SettingsReportHandler.ps1"
        [System.Windows.MessageBox]::Show("Failed to generate settings report: $($_.Exception.Message)", "Error")
    }
})
