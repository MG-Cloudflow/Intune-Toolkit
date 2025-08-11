<#
.SYNOPSIS
Handles the click event for the SearchButton to filter and display policy data based on the search query.

.DESCRIPTION
This script is triggered when the SearchButton is clicked. It retrieves the search query and selected field, filters the global policy data based on the query, and updates the PolicyDataGrid with the filtered results. It includes logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
$SearchButton.Add_Click({
    # Code to handle click event
})
#>

$SearchButton.Add_Click({
    Write-IntuneToolkitLog "SearchButton clicked" -component "Search-Button" -file "SearchButton.ps1"

    try {
        $searchQuery = $SearchBox.Text.ToLower()
        $selectedField = $SearchFieldComboBox.SelectedItem.Tag

        Write-IntuneToolkitLog "Search query: $searchQuery" -component "Search-Button" -file "SearchButton.ps1"
        Write-IntuneToolkitLog "Selected field: $selectedField" -component "Search-Button" -file "SearchButton.ps1"

        if (-not [string]::IsNullOrWhiteSpace($searchQuery)) {
            $filteredData = $global:AllPolicyData | Where-Object {
                $_.$selectedField.ToLower().Contains($searchQuery)
            }
            Write-IntuneToolkitLog "Filtered data count: $($filteredData.Count)" -component "Search-Button" -file "SearchButton.ps1"
        } else {
            $filteredData = $global:AllPolicyData
            Write-IntuneToolkitLog "No search query provided, using all policy data" -component "Search-Button" -file "SearchButton.ps1"
        }

        # Ensure filteredData is a collection
        if ($filteredData -isnot [System.Collections.IEnumerable]) {
            $filteredData = @($filteredData)
            Write-IntuneToolkitLog "Filtered data converted to collection" -component "Search-Button" -file "SearchButton.ps1"
        }

        # Apply additional filter clauses
        Write-IntuneToolkitLog "AdditionalFiltersPanel child count: $($AdditionalFiltersPanel.Children.Count)" -component "Search-Button" -file "SearchButton.ps1"
        $clauseIndex = 0
        foreach ($clausePanel in $AdditionalFiltersPanel.Children) {
            $clauseIndex++
            Write-IntuneToolkitLog "Processing clause #$clauseIndex" -component "Search-Button" -file "SearchButton.ps1"
            # Find operator and field dropdowns and term textbox
            $combos = $clausePanel.Children | Where-Object { $_ -is [System.Windows.Controls.ComboBox] }
            $textBox = $clausePanel.Children | Where-Object { $_ -is [System.Windows.Controls.TextBox] }
            Write-IntuneToolkitLog "Found COMBOS:$($combos.Count), TextBox present:$([bool]$textBox)" -component "Search-Button" -file "SearchButton.ps1"
            if ($combos.Count -ge 2 -and $textBox) {
                # Determine operator (items may be strings or ComboBoxItems)
                $opItem = $combos[0].SelectedItem
                if ($opItem -is [System.Windows.Controls.ComboBoxItem]) { $op = $opItem.Content } else { $op = $opItem }
                # Determine field tag
                $fieldItem = $combos[1].SelectedItem
                if ($fieldItem -is [System.Windows.Controls.ComboBoxItem]) { $fieldTag = $fieldItem.Tag } else { $fieldTag = $fieldItem.Tag }
                $termVal = $textBox.Text.ToLower()
                Write-IntuneToolkitLog "Clause #$clauseIndex details -> op:$op, fieldTag:$fieldTag, termVal:'$termVal'" -component "Search-Button" -file "SearchButton.ps1"
                if (-not [string]::IsNullOrWhiteSpace($termVal)) {
                    if ($op -eq 'AND') {
                        $filteredData = $filteredData | Where-Object { $_.$fieldTag -and $_.$fieldTag.ToLower().Contains($termVal) }
                    } elseif ($op -eq 'OR') {
                        $orMatches = $global:AllPolicyData | Where-Object { $_.$fieldTag -and $_.$fieldTag.ToLower().Contains($termVal) }
                        foreach ($item in $orMatches) { if ($filteredData -notcontains $item) { $filteredData += $item } }
                    }
                }
            }
        }
        # Ensure collection
        if ($filteredData -isnot [System.Collections.IEnumerable]) { $filteredData = @($filteredData) }
        # Update DataGrid
        $PolicyDataGrid.ItemsSource = $filteredData
        $PolicyDataGrid.Items.Refresh()
        Write-IntuneToolkitLog "PolicyDataGrid updated with filtered data" -component "Search-Button" -file "SearchButton.ps1"
    } catch {
        $errorMessage = "Failed to search and filter policy data. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Search-Button" -file "SearchButton.ps1"
    }
})

<# function Refresh-Grid {
    $searchQuery = $SearchBox.Text.ToLower()
    $selectedField = $SearchFieldComboBox.SelectedItem.Tag

    if (-not [string]::IsNullOrWhiteSpace($searchQuery)) {
        $filteredData = $global:AllPolicyData | Where-Object {
            $_.$selectedField.ToLower().Contains($searchQuery)
        }
    } else {
        $filteredData = $global:AllPolicyData
    }

    # Ensure filteredData is a collection
    if ($filteredData -isnot [System.Collections.IEnumerable]) {
        $filteredData = @($filteredData)
    }

    $PolicyDataGrid.ItemsSource = $filteredData
}

# Initial population of the group combo box
Refresh-Grid

# Add event handler for the search box text change
$SearchBox.Add_TextChanged({
    Refresh-Grid
}) #>
