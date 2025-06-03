<#
.SYNOPSIS
Displays a selection dialog for groups, filters, assignment type, and (optionally) intent for policy assignments.
Disables filter fields and enforces that if one filter field is filled, both must be filled.

.DESCRIPTION
This function loads a XAML-based selection dialog and populates its controls for group, filter, filter type, 
assignment type, and (optionally) intent. If the global policy type is one of 
deviceCustomAttributeShellScripts, intents, deviceShellScripts, or deviceManagementScripts, the filter fields 
are disabled. Additionally, if either filter field is filled in while the other is left blank, the user is 
prompted to complete both before continuing. The user selection is returned as a PSCustomObject.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 09/07/2024

.EXAMPLE
$result = Show-SelectionDialog -groups $groupList -filters $filterList -includeIntent $true
if ($result) {
    # Process the returned selection
}
#>
function Show-SelectionDialog {
    param (
        [Parameter(Mandatory = $true)]
        [array]$groups,
        [Parameter(Mandatory = $false)]
        [array]$filters,
        [Parameter(Mandatory = $false)]
        [bool]$includeIntent = $false,
        [Parameter(Mandatory = $false)]
        [string]$appODataType
    )

    Write-IntuneToolkitLog "Show-SelectionDialog function called" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    # ---------------------------------------------------------------------------
    # Load the XAML file for the selection dialog.
    # ---------------------------------------------------------------------------
    $xamlPath = ".\XML\SelectionDialog.xaml"  # Ensure this path is correct
    if (-not (Test-Path $xamlPath)) {
        $errorMessage = "XAML file not found at $xamlPath"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return $null
    }

    [xml]$xaml = Get-Content $xamlPath
    Write-IntuneToolkitLog "Loaded XAML content from $xamlPath" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    if (-not $Window) {
        $errorMessage = "Failed to load XAML"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return $null
    }
    Write-IntuneToolkitLog "XAML loaded successfully" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    # ---------------------------------------------------------------------------
    # Retrieve UI elements from the dialog.
    # ---------------------------------------------------------------------------
    $GroupSearchBox         = $Window.FindName("GroupSearchBox")
    $GroupComboBox          = $Window.FindName("GroupComboBox")
    $FilterComboBox         = $Window.FindName("FilterComboBox")
    $FilterTypeComboBox     = $Window.FindName("FilterTypeComboBox")
    $AssignmentTypeComboBox = $Window.FindName("AssignmentTypeComboBox")
    $IntentComboBox         = $Window.FindName("IntentComboBox")
    $IntentTextBlock        = $Window.FindName("IntentTextBlock")
    $OkButton               = $Window.FindName("OkButton")
    $CancelButton           = $Window.FindName("CancelButton")

    # ---------------------------------------------------------------------------
    # Validate that all required UI elements are found.
    # ---------------------------------------------------------------------------
    if (-not $GroupSearchBox) { Write-Error "GroupSearchBox not found"; Write-IntuneToolkitLog "GroupSearchBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $GroupComboBox) { Write-Error "GroupComboBox not found"; Write-IntuneToolkitLog "GroupComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $FilterComboBox) { Write-Error "FilterComboBox not found"; Write-IntuneToolkitLog "FilterComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $FilterTypeComboBox) { Write-Error "FilterTypeComboBox not found"; Write-IntuneToolkitLog "FilterTypeComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $AssignmentTypeComboBox) { Write-Error "AssignmentTypeComboBox not found"; Write-IntuneToolkitLog "AssignmentTypeComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $OkButton) { Write-Error "OkButton not found"; Write-IntuneToolkitLog "OkButton not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $CancelButton) { Write-Error "CancelButton not found"; Write-IntuneToolkitLog "CancelButton not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if ($includeIntent -and (-not $IntentComboBox)) { Write-Error "IntentComboBox not found"; Write-IntuneToolkitLog "IntentComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }

    Write-IntuneToolkitLog "UI elements found successfully" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    # ---------------------------------------------------------------------------
    # Set intent controls visible if included.
    # ---------------------------------------------------------------------------
    if ($includeIntent) {
        $IntentComboBox.Visibility = "Visible"
        $IntentTextBlock.Visibility = "Visible"
    }

    # ---------------------------------------------------------------------------
    # Disable filter fields for specific policy types.
    # ---------------------------------------------------------------------------
    if (
        $global:CurrentPolicyType -in @(
            "deviceCustomAttributeShellScripts",
            "intents",
            "deviceShellScripts",
            "deviceManagementScripts"
        ) -or
        $appODataType -in @(
            "#microsoft.graph.macOSDmgApp",
            "#microsoft.graph.macOSPkgApp"
        )
    ) {
        $FilterComboBox.IsEnabled = $false
        $FilterTypeComboBox.IsEnabled = $false
        Write-IntuneToolkitLog "Filter fields disabled due to policy type or app type: $global:CurrentPolicyType / $appODataType" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
    } else {
        $FilterComboBox.IsEnabled = $true
        $FilterTypeComboBox.IsEnabled = $true
    }

    # ---------------------------------------------------------------------------
    # Populate the group combo box based on the search text.
    # ---------------------------------------------------------------------------
    function Refresh-GroupComboBox {
        $GroupComboBox.Items.Clear()
        $searchText = $GroupSearchBox.Text.ToLower()
        foreach ($group in $groups) {
            if ($group.DisplayName -and $group.DisplayName.ToLower().Contains($searchText)) {
                $comboBoxItem = New-Object Windows.Controls.ComboBoxItem
                $comboBoxItem.Content = $group.DisplayName
                $comboBoxItem.Tag = $group.Id
                $GroupComboBox.Items.Add($comboBoxItem)
            }
        }
    }
    Refresh-GroupComboBox
    Write-IntuneToolkitLog "Initial population of group combo box completed" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    # Update the group combo box as the user types.
    $GroupSearchBox.Add_TextChanged({ Refresh-GroupComboBox })

    # ---------------------------------------------------------------------------
    # Populate the filter combo box.
    # ---------------------------------------------------------------------------
    if ($null -ne $filters) {
        foreach ($filter in $filters) {
            $comboBoxItem = New-Object Windows.Controls.ComboBoxItem
            $comboBoxItem.Content = $filter.displayName
            $comboBoxItem.Tag = $filter.id
            $FilterComboBox.Items.Add($comboBoxItem)
        }
        Write-IntuneToolkitLog "Populated filter combo box" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
    } else {
        $comboBoxItem = New-Object Windows.Controls.ComboBoxItem
        $comboBoxItem.Content = "No Filters"
        $FilterComboBox.Items.Add($comboBoxItem)
        Write-IntuneToolkitLog "No filters available to populate filter combo box" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
    }

    # ---------------------------------------------------------------------------
    # Populate the filter type combo box with include and exclude options.
    # ---------------------------------------------------------------------------
    $includeItem = New-Object Windows.Controls.ComboBoxItem
    $includeItem.Content = "include"
    $FilterTypeComboBox.Items.Add($includeItem)

    $excludeItem = New-Object Windows.Controls.ComboBoxItem
    $excludeItem.Content = "exclude"
    $FilterTypeComboBox.Items.Add($excludeItem)
    Write-IntuneToolkitLog "Populated filter type combo box with include and exclude options" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    # ---------------------------------------------------------------------------
    # Populate intent options if required.
    # ---------------------------------------------------------------------------
    if ($includeIntent) {
        if ($IntentComboBox.Items.Count -eq 0) {
            $availableItem = New-Object Windows.Controls.ComboBoxItem
            $availableItem.Content = "Available"
            $IntentComboBox.Items.Add($availableItem)

            $requiredItem = New-Object Windows.Controls.ComboBoxItem
            $requiredItem.Content = "Required"
            $IntentComboBox.Items.Add($requiredItem)

            $uninstallItem = New-Object Windows.Controls.ComboBoxItem
            $uninstallItem.Content = "Uninstall"
            $IntentComboBox.Items.Add($uninstallItem)
            Write-IntuneToolkitLog "Populated intent combo box with available, required, and uninstall options" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        }
    }

    # ---------------------------------------------------------------------------
    # Initialize the selection object.
    # ---------------------------------------------------------------------------
    $selection = [PSCustomObject]@{
        Group          = $null
        Filter         = $null
        FilterType     = $null
        AssignmentType = $null
        Intent         = $null
    }

    # ---------------------------------------------------------------------------
    # OK button event: capture user selections and enforce filter safety.
    # ---------------------------------------------------------------------------
    $OkButton.Add_Click({
        # Safety check: if one filter field is filled in while the other is not, prompt the user.
        if ($FilterComboBox.IsEnabled -and (
                ($FilterComboBox.SelectedItem -and -not $FilterTypeComboBox.SelectedItem) -or
                (-not $FilterComboBox.SelectedItem -and $FilterTypeComboBox.SelectedItem)
            )) {
            [System.Windows.MessageBox]::Show("If you wish to apply a filter, please select both a filter and a filter type.","Incomplete Filter Selection")
            return  # Do not close the window
        }

        # Capture the user's selections.
        $selection.Group = $GroupComboBox.SelectedItem
        $selection.Filter = $FilterComboBox.SelectedItem
        $selection.FilterType = $FilterTypeComboBox.SelectedItem
        $selection.AssignmentType = $AssignmentTypeComboBox.SelectedItem
        if ($includeIntent) {
            $selection.Intent = $IntentComboBox.SelectedItem.Content
        }
        Write-Output "Selected Group: $($selection.Group.Content) - $($selection.Group.Tag)"
        Write-Output "Selected Filter: $($selection.Filter.Content) - $($selection.Filter.Tag)"
        Write-Output "Selected Filter Type: $($selection.FilterType.Content)"
        Write-Output "Selected Assignment Type: $($selection.AssignmentType.Content)"
        if ($includeIntent) {
            Write-Output "Selected Intent: $($selection.Intent)"
        }
        Write-IntuneToolkitLog "Selection made - Group: $($selection.Group.Content), Filter: $($selection.Filter.Content), Filter Type: $($selection.FilterType.Content), Assignment Type: $($selection.AssignmentType.Content), Intent: $($selection.Intent)" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        $Window.Close()
    })

    # ---------------------------------------------------------------------------
    # Cancel button event: close the dialog.
    # ---------------------------------------------------------------------------
    $CancelButton.Add_Click({
        Write-IntuneToolkitLog "Selection dialog canceled by user" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        $Window.Close()
    })
    Set-WindowIcon -Window $Window
    $Window.ShowDialog() | Out-Null

    # ---------------------------------------------------------------------------
    # Return the selection if a group was chosen; otherwise, log an error.
    # ---------------------------------------------------------------------------
    if ($selection.Group -and $selection.Group.Tag) {
        Write-IntuneToolkitLog "Returning selected items" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return @{
            Group          = $selection.Group
            Filter         = $selection.Filter
            FilterType     = if ($selection.FilterType) { $selection.FilterType.Content } else { $null }
            AssignmentType = if ($selection.AssignmentType) { $selection.AssignmentType.Content } else { "Include" }
            Intent         = $selection.Intent
        }
    } else {
        $errorMessage = "No group selected"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return $null
    }
}
