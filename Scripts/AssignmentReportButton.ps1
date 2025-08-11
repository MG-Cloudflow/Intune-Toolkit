<#
.SYNOPSIS
Handles unified AssignmentReportButton click: choose export formats and perform CSV/Markdown exports.
.DESCRIPTION
Opens dialog to select export formats, then runs inline export logic without needing separate scripts.
#>

# Utility: get selected or all policies
function Get-PoliciesToExport {
    param(
        [PSObject]$AllPolicies,
        [System.Windows.Controls.DataGrid]$DataGrid
    )
    $selected = $DataGrid.SelectedItems
    if ($selected.Count -gt 0) {
        $ids = $selected | Select-Object -ExpandProperty PolicyId -Unique
        return $AllPolicies | Where-Object { $ids -contains $_.PolicyId }
    }
    return $AllPolicies
}

# Markdown export function with detailed formatting
function Export-ToMarkdown {
    param(
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][PSObject]$PolicyDataGrid,
        [Parameter(Mandatory=$true)][string]$CurrentPolicyType
    )
    try {
        # Retrieve tenant info and current date
        $tenant = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
        $tenantInfo = "Tenant: $($tenant.value[0].displayName)"
        $dateString = Get-Date -Format "dddd, MMMM dd, yyyy HH:mm:ss"
        # Build header
        $header = "# $CurrentPolicyType`n`n$tenantInfo`n`nDocumentation Date: $dateString`n`n"
        # Table of contents
        $toc = "## Table of Contents`n`n"
        # Main content
        $content = ""
        $groups = $PolicyDataGrid | Group-Object PolicyId | Sort-Object { $_.Group[0].Platform }, { $_.Group[0].PolicyName }
        $currentPlatform = ""
        foreach ($policyGroup in $groups) {
            $first = $policyGroup.Group[0]
            if ($currentPlatform -ne $first.Platform) {
                $currentPlatform = $first.Platform
                $content += "## Platform: $currentPlatform`n`n"
                $toc += "- [$currentPlatform](#$(($currentPlatform -replace ' ','-').ToLower()))`n"
            }
            $policyName = $first.PolicyName
            $toc += "  - [$policyName](#$(($policyName -replace ' ','-').ToLower()))`n"
            $content += "### $policyName`n`n"
            $content += "#### Description`n`n$($first.PolicyDescription)`n`n"
            $content += "#### Assignments`n`n"
            # Table header
            if ($CurrentPolicyType -eq 'mobileApps') {
                $content += "| GroupDisplayname | GroupId | Platform | AssignmentType | FilterDisplayname | FilterType | InstallIntent |`n"
                $content += "| --------------- | ------- | -------- | -------------- | ----------------- | ---------- | ------------- |`n"
            } elseif ($CurrentPolicyType -in @('deviceCustomAttributeShellScripts','intents','deviceShellScripts','deviceManagementScripts')) {
                $content += "| GroupDisplayname | GroupId | Platform | AssignmentType |`n"
                $content += "| --------------- | ------- | -------- | -------------- |`n"
            } else {
                $content += "| GroupDisplayname | GroupId | Platform | AssignmentType | FilterDisplayname | FilterType |`n"
                $content += "| --------------- | ------- | -------- | -------------- | ----------------- | ---------- |`n"
            }
            foreach ($item in $policyGroup.Group) {
                if ($CurrentPolicyType -eq 'mobileApps') {
                    $content += "| $($item.GroupDisplayname) | $($item.GroupId) | $($item.Platform) | $($item.AssignmentType) | $($item.FilterDisplayname) | $($item.FilterType) | $($item.InstallIntent) |`n"
                } elseif ($CurrentPolicyType -in @('deviceCustomAttributeShellScripts','intents','deviceShellScripts','deviceManagementScripts')) {
                    $content += "| $($item.GroupDisplayname) | $($item.GroupId) | $($item.Platform) | $($item.AssignmentType) |`n"
                } else {
                    $content += "| $($item.GroupDisplayname) | $($item.GroupId) | $($item.Platform) | $($item.AssignmentType) | $($item.FilterDisplayname) | $($item.FilterType) |`n"
                }
            }
            $content += "`n"
        }
        # Combine and write
        $final = "$header`n$toc`n$content"
        $final | Out-File -FilePath $OutputPath -Encoding utf8
        Write-IntuneToolkitLog -Message "Exported policy data to Markdown file at $OutputPath" -Component "ExportToMarkdown"
        [System.Windows.MessageBox]::Show('Markdown export completed successfully.','Export Completed',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information)
    } catch {
        Write-IntuneToolkitLog -Message "An error occurred during Markdown export: $_" -Component "ExportToMarkdown" -Severity "Error"
        [System.Windows.MessageBox]::Show("An error occurred during Markdown export: $_","Export Failed",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)
    }
}

# CSV export function
function Export-ToCsv {
    param(
        [string]$OutputPath,
        [PSObject]$PolicyItems
    )
    try {
        $PolicyItems | Export-Csv -Path $OutputPath -NoTypeInformation
        [System.Windows.MessageBox]::Show('CSV export succeeded','Success',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information)
    } catch {
        [System.Windows.MessageBox]::Show("CSV export failed: $_","Error",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)
    }
}

# Handler for Assignment Report button
$AssignmentReportButton.Add_Click({
    try {
        Write-IntuneToolkitLog "AssignmentReportButton clicked" -component "AssignmentReport-Button" -file "AssignmentReportButton.ps1"

        # Get items to export (selected or all)
        $policies = Get-PoliciesToExport -AllPolicies $global:AllPolicyData -DataGrid $PolicyDataGrid
        if (-not $policies -or $policies.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No policies to export.", "Information")
            return
        }

        # Show export format options
        $formats = Show-ExportOptionsDialog
        if (-not $formats -or $formats.Count -eq 0) { return }

        # Ensure Windows Forms types
        Add-Type -AssemblyName System.Windows.Forms
        $baseName = "AssignmentReport_$($global:CurrentPolicyType)_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"

        foreach ($fmt in $formats) {
            switch ($fmt) {
                'Markdown' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'Markdown (*.md)|*.md|All (*.*)|*.*'
                    $dlg.Title    = 'Save Assignment Report as Markdown'
                    $dlg.FileName = "$baseName.md"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        Export-ToMarkdown -OutputPath $dlg.FileName -PolicyDataGrid $policies -CurrentPolicyType $global:CurrentPolicyType
                    }
                }
                'CSV' {
                    $dlg = New-Object System.Windows.Forms.SaveFileDialog
                    $dlg.Filter   = 'CSV (*.csv)|*.csv|All (*.*)|*.*'
                    $dlg.Title    = 'Save Assignment Report as CSV'
                    $dlg.FileName = "$baseName.csv"
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        Export-ToCsv -OutputPath $dlg.FileName -PolicyItems $policies
                    }
                }
            }
        }

        [System.Windows.MessageBox]::Show("Export complete.", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } catch {
        Write-IntuneToolkitLog "Error in AssignmentReportButton: $_" -component "AssignmentReport-Button" -file "AssignmentReportButton.ps1"
        [System.Windows.MessageBox]::Show("Failed to generate assignment report: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})
