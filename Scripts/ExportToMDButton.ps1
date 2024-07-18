<#
.SYNOPSIS
Exports policy data loaded in the grid to a Markdown file.

.DESCRIPTION
This script exports the policy data from the Intune Toolkit grid to a Markdown file.
It generates the Markdown content including the policy name, description, and assignments.
If the policy type is mobileApps, it also includes the InstallIntent in the output.

.PARAMETER MainWindow
The main window of the Intune Toolkit application.

.PARAMETER dataGridItems
The policy data loaded in the grid that needs to be exported.

.NOTES

Author: Maxime Guillemin | CloudFlow
Date: 09/07/2024

This script adds a button to the Intune Toolkit interface that allows users to export 
policy data to a Markdown file. The export process includes handling for selected policies 
or all policies if none are selected, and incorporates detailed error handling and logging.
#>

# Event handler for the Export to Markdown button click event
$ExportToMDButton.Add_Click({
    
    <#
    .SYNOPSIS
    Exports the provided policy data to a Markdown file.

    .DESCRIPTION
    This function takes the policy data and generates a Markdown file, 
    organizing the data by policy name, description, and assignments. 
    It handles different columns for mobileApps policy type.

    .PARAMETER OutputPath
    The file path where the Markdown file will be saved.

    .PARAMETER PolicyDataGrid
    The collection of policy data to be exported.

    .PARAMETER CurrentPolicyType
    The type of policies being exported, used to determine specific columns.
    #>
    function Export-ToMarkdown {
        param (
            [Parameter(Mandatory=$true)]
            [string]$OutputPath,

            [Parameter(Mandatory=$true)]
            [PSObject]$PolicyDataGrid,

            [string]$CurrentPolicyType
        )

        try {
            $tenant = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
            $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/me" -Method GET
            $tenantinfo = "Tenant: $($tenant.value[0].displayName)"
            $dateString = Get-Date -Format "dddd, MMMM dd, yyyy HH:mm:ss"
            $markdownContent = ""
            $markdownContentHeader =""
            $tocContent = "## Table of Contents`n`n"
            $markdownContentHeader += "# $global:CurrentPolicyType`n`n"
            $markdownContentHeader += "$tenantinfo`n`n"
            $markdownContentHeader += "Documentation Date: $dateString`n`n"

            # Group policies by PolicyId and sort by Platform and PolicyName
            $uniquePolicies = $PolicyDataGrid | Group-Object -Property PolicyId | Sort-Object { $_.Group[0].Platform }, { $_.Group[0].PolicyName }

            $currentPlatform = ""
            foreach ($policyGroup in $uniquePolicies) {
                $firstPolicy = $policyGroup.Group[0]
                $PolicyName = $firstPolicy.PolicyName
                $PolicyDescription = $firstPolicy.PolicyDescription
                $PolicyPlatform = $firstPolicy.Platform

                # Add platform title if it has changed
                if ($currentPlatform -ne $PolicyPlatform) {
                    $currentPlatform = $PolicyPlatform
                    $markdownContent += "## $($currentPlatform)`n`n"
                    $tocContent += "- [$($currentPlatform)](#$($currentPlatform.ToLower())-applications)`n"
                }

                # Add policy name to TOC
                $tocContent += "  - [$($PolicyName)](#$(($PolicyName -replace ' ', '-').ToLower()))`n"

                # Add policy name and description to markdown content
                $markdownContent += "### $($PolicyName)`n`n"
                $markdownContent += "#### Description`n`n"
                $markdownContent += "$($PolicyDescription)`n`n"
                $markdownContent += "#### Assignments`n`n"
                
                # Add table headers based on policy type
                if ($CurrentPolicyType -eq "mobileApps") {
                    $markdownContent += "| GroupDisplayname | GroupId | AssignmentType | FilterDisplayname | FilterType | InstallIntent |`n"
                    $markdownContent += "| ---------------- | ------- | -------------- | ----------------- | ---------- | ------------- |`n"
                } else {
                    $markdownContent += "| GroupDisplayname | GroupId | AssignmentType | FilterDisplayname | FilterType |`n"
                    $markdownContent += "| ---------------- | ------- | -------------- | ----------------- | ---------- |`n"
                }

                # Add each assignment to the markdown table
                foreach ($policy in $policyGroup.Group) {
                    $GroupDisplayname = $policy.GroupDisplayname
                    $GroupId = $policy.GroupId
                    $AssignmentType = $policy.AssignmentType
                    $FilterDisplayname = $policy.FilterDisplayname
                    $FilterType = $policy.FilterType
                    $InstallIntent = $policy.InstallIntent

                    if ($CurrentPolicyType -eq "mobileApps") {
                        $markdownContent += "| $GroupDisplayname | $GroupId | $AssignmentType | $FilterDisplayname | $FilterType | $InstallIntent |`n"
                    } else {
                        $markdownContent += "| $GroupDisplayname | $GroupId | $AssignmentType | $FilterDisplayname | $FilterType |`n"
                    }
                }

                $markdownContent += "`n`n"
            }

            # Combine TOC and main content
            $finalContent = "$markdownContentHeader`n$tocContent`n$markdownContent"

            # Write the markdown content to a file
            try {
                $finalContent | Out-File -FilePath $OutputPath -Encoding utf8
                Write-IntuneToolkitLog -Message "Exported policy data to Markdown file at $OutputPath" -Component "ExportToMarkdown"
            }
            catch {
                Write-IntuneToolkitLog -Message "Failed to write to file: $_" -Component "ExportToMarkdown" -Severity "Error"
                [System.Windows.MessageBox]::Show("Failed to write to file: $_", "Export Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }
        }
        catch {
            Write-IntuneToolkitLog -Message "An error occurred during Markdown export: $_" -Component "ExportToMarkdown" -Severity "Error"
            [System.Windows.MessageBox]::Show("An error occurred during Markdown export: $_", "Export Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }

    <#
    .SYNOPSIS
    Retrieves policies to be exported based on user selection.

    .DESCRIPTION
    This function checks if any policies are selected in the DataGrid. 
    If selected policies exist, it returns those. Otherwise, it returns all policies.

    .PARAMETER AllPolicies
    The collection of all policies available for export.

    .PARAMETER DataGrid
    The DataGrid control containing the policies.

    .RETURNS
    The policies to be exported.
    #>
    function Get-PoliciesToExport {
        param (
            [PSObject]$AllPolicies,
            [System.Windows.Controls.DataGrid]$DataGrid
        )
        
        try {
            $selectedItems = $DataGrid.SelectedItems
            if ($selectedItems.Count -gt 0) {
                # Get unique policy IDs from the selected items
                $selectedPolicyIds = $selectedItems | Select-Object -ExpandProperty PolicyId -Unique
                # Return all assignments for the selected policies
                return $AllPolicies | Where-Object { $selectedPolicyIds -contains $_.PolicyId }
            } else {
                return $AllPolicies
            }
        }
        catch {
            Write-IntuneToolkitLog -Message "Failed to get policies to export: $_" -Component "ExportToMarkdown" -Severity "Error"
            [System.Windows.MessageBox]::Show("Failed to get policies to export: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            throw
        }
    }

    # Open a Save File Dialog to select the output path
    $saveFileDialog = New-Object -TypeName Microsoft.Win32.SaveFileDialog
    $saveFileDialog.Filter = "Markdown files (*.md)|*.md"
    $saveFileDialog.DefaultExt = "md"
    $saveFileDialog.AddExtension = $true

    try {
        if ($saveFileDialog.ShowDialog() -eq $true) {
            $outputPath = $saveFileDialog.FileName
            Write-IntuneToolkitLog -Message "Initiating export to Markdown" -Component "ExportToMarkdown"
            
            $policiesToExport = Get-PoliciesToExport -AllPolicies $global:AllPolicyData -DataGrid $PolicyDataGrid
            Export-ToMarkdown -OutputPath $outputPath -PolicyDataGrid $policiesToExport -CurrentPolicyType $global:CurrentPolicyType
            
            [System.Windows.MessageBox]::Show("Export to Markdown completed successfully.", "Export Completed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            Write-IntuneToolkitLog -Message "Export to Markdown completed successfully." -Component "ExportToMarkdown"
        } else {
            [System.Windows.MessageBox]::Show("Export to Markdown was canceled.", "Export Canceled", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            Write-IntuneToolkitLog -Message "Export to Markdown was canceled by user." -Component "ExportToMarkdown"
        }
    }
    catch {
        Write-IntuneToolkitLog -Message "An error occurred during the export process: $_" -Component "ExportToMarkdown" -Severity "Error"
        [System.Windows.MessageBox]::Show("An error occurred during the export process: $_", "Export Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})
