<#
.SYNOPSIS
Handles the click event for the AdminTemplatesButton, setting the current policy type to groupPolicyConfigurations and loading the respective policy data.

.DESCRIPTION
This script is triggered when the AdminTemplatesButton is clicked. It sets the global policy type to groupPolicyConfigurations and calls the Load-PolicyData function to load the administrative templates. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$AdminTemplatesButton.Add_Click({
    # Code to handle click event
})
#>
function Show-SelectionDialog {
    param (
        [Parameter(Mandatory = $true)]
        [array]$groups,
        [Parameter(Mandatory = $true)]
        [array]$filters,
        [Parameter(Mandatory = $false)]
        [bool]$includeIntent = $false
    )

    Write-IntuneToolkitLog "Show-SelectionDialog function called" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    $xamlPath = ".\XML\SelectionDialog.xaml"  # Ensure this path is correct
    if (-not (Test-Path $xamlPath)) {
        $errorMessage = "XAML file not found at $xamlPath"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return $null
    }

    [xml]$xaml = Get-Content $xamlPath
    Write-IntuneToolkitLog "Loaded XAML content from $xamlPath" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    if (-not $Window) {
        $errorMessage = "Failed to load XAML"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return $null
    }
    Write-IntuneToolkitLog "XAML loaded successfully" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    $GroupSearchBox = $Window.FindName("GroupSearchBox")
    $GroupComboBox = $Window.FindName("GroupComboBox")
    $FilterComboBox = $Window.FindName("FilterComboBox")
    $FilterTypeComboBox = $Window.FindName("FilterTypeComboBox")
    $AssignmentTypeComboBox = $Window.FindName("AssignmentTypeComboBox")
    $IntentComboBox = $Window.FindName("IntentComboBox")
    $IntentTextBlock = $Window.FindName("IntentTextBlock")
    $OkButton = $Window.FindName("OkButton")
    $CancelButton = $Window.FindName("CancelButton")

    if (-not $GroupSearchBox) { Write-Error "GroupSearchBox not found"; Write-IntuneToolkitLog "GroupSearchBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $GroupComboBox) { Write-Error "GroupComboBox not found"; Write-IntuneToolkitLog "GroupComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $FilterComboBox) { Write-Error "FilterComboBox not found"; Write-IntuneToolkitLog "FilterComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $FilterTypeComboBox) { Write-Error "FilterTypeComboBox not found"; Write-IntuneToolkitLog "FilterTypeComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $AssignmentTypeComboBox) { Write-Error "AssignmentTypeComboBox not found"; Write-IntuneToolkitLog "AssignmentTypeComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $OkButton) { Write-Error "OkButton not found"; Write-IntuneToolkitLog "OkButton not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if (-not $CancelButton) { Write-Error "CancelButton not found"; Write-IntuneToolkitLog "CancelButton not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }
    if ($includeIntent -and (-not $IntentComboBox)) { Write-Error "IntentComboBox not found"; Write-IntuneToolkitLog "IntentComboBox not found" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"; return $null }

    Write-IntuneToolkitLog "UI elements found successfully" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    if ($includeIntent) {
        $IntentComboBox.Visibility = "Visible"
        $IntentTextBlock.Visibility = "Visible"
    }

    # Function to refresh the group combo box based on search text
    function Refresh-GroupComboBox {
        $GroupComboBox.Items.Clear()
        $searchText = $GroupSearchBox.Text.ToLower()
        foreach ($group in $groups) {
            if ($group.DisplayName.ToLower().Contains($searchText)) {
                $comboBoxItem = New-Object Windows.Controls.ComboBoxItem
                $comboBoxItem.Content = $group.DisplayName
                $comboBoxItem.Tag = $group.Id
                $GroupComboBox.Items.Add($comboBoxItem)
            }
        }
    }

    # Initial population of the group combo box
    Refresh-GroupComboBox
    Write-IntuneToolkitLog "Initial population of group combo box completed" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    # Add event handler for the search box text change
    $GroupSearchBox.Add_TextChanged({
        Refresh-GroupComboBox
    })

    foreach ($filter in $filters) {
        $comboBoxItem = New-Object Windows.Controls.ComboBoxItem
        $comboBoxItem.Content = $filter.displayName
        $comboBoxItem.Tag = $filter.id
        $FilterComboBox.Items.Add($comboBoxItem)
    }
    Write-IntuneToolkitLog "Populated filter combo box" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    # Add include and exclude options to the FilterTypeComboBox
    $includeItem = New-Object Windows.Controls.ComboBoxItem
    $includeItem.Content = "include"
    $FilterTypeComboBox.Items.Add($includeItem)

    $excludeItem = New-Object Windows.Controls.ComboBoxItem
    $excludeItem.Content = "exclude"
    $FilterTypeComboBox.Items.Add($excludeItem)
    Write-IntuneToolkitLog "Populated filter type combo box with include and exclude options" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"

    if ($includeIntent) {
        # Ensure intent options are not duplicated
        if ($IntentComboBox.Items.Count -eq 0) {
            # Add intent options to the IntentComboBox
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

    $selection = [PSCustomObject]@{
        Group = $null
        Filter = $null
        FilterType = $null
        AssignmentType = $null
        Intent = $null
    }

    $OkButton.Add_Click({
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

    $CancelButton.Add_Click({
        $Window.Close()
        Write-IntuneToolkitLog "Selection dialog canceled by user" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
    })

    $Window.ShowDialog() | Out-Null

    if ($selection.Group -and $selection.Group.Tag) {
        Write-IntuneToolkitLog "Returning selected items" -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return @{
            Group = $selection.Group
            Filter = $selection.Filter
            FilterType = if ($selection.FilterType) { $selection.FilterType.Content } else { $null }
            AssignmentType = if ($selection.AssignmentType) { $selection.AssignmentType.Content } else { "Include" }
            Intent = $selection.Intent
        }
    } else {
        $errorMessage = "No group selected"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Show-SelectionDialog" -file "SelectionDialog.ps1"
        return $null
    }
}
