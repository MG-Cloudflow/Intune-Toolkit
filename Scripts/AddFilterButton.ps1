# Add additional filters on AddFilterButton click
# Relies on $AddFilterButton and $AdditionalFiltersPanel variables defined in Main.ps1

$AddFilterButton.Add_Click({
    # Horizontal panel for one clause
    $clausePanel = New-Object System.Windows.Controls.StackPanel
    $clausePanel.Orientation = 'Horizontal'
    # Operator dropdown
    $opCombo = New-Object System.Windows.Controls.ComboBox
    $opCombo.Width = 60
    $opCombo.Style = $SearchFieldComboBox.Style
    $opCombo.Height = $SearchFieldComboBox.Height
    $opCombo.Margin = '5'
    $opCombo.Items.Add('AND') | Out-Null
    $opCombo.Items.Add('OR')  | Out-Null
    $opCombo.SelectedIndex = 0
    # Field dropdown cloned from SearchFieldComboBox
    $fieldCombo = New-Object System.Windows.Controls.ComboBox
    $fieldCombo.Width = 150
    $fieldCombo.Style = $SearchFieldComboBox.Style
    $fieldCombo.Height = $SearchFieldComboBox.Height
    $fieldCombo.Margin = '5'
    foreach ($item in $SearchFieldComboBox.Items) {
        $clone = New-Object System.Windows.Controls.ComboBoxItem
        $clone.Content = $item.Content
        $clone.Tag     = $item.Tag
        $fieldCombo.Items.Add($clone) | Out-Null
    }
    $fieldCombo.SelectedIndex = 0
    # Term textbox
    $termBox = New-Object System.Windows.Controls.TextBox
    $termBox.Width = 200
    $termBox.Margin = '5'
    # Remove clause button
    $removeBtn = New-Object System.Windows.Controls.Button
    $removeBtn.Content = '-'
    $removeBtn.Width   = 30
    $removeBtn.Style   = $AddFilterButton.Style
    $removeBtn.Margin  = '5'
    # Remove clause panel when clicked (remove sender's parent panel)
    $removeBtn.Add_Click({ param($sender,$e) $AdditionalFiltersPanel.Children.Remove($sender.Parent) })
    # Assemble clause panel
    $clausePanel.Children.Add($opCombo)
    $clausePanel.Children.Add($fieldCombo)
    $clausePanel.Children.Add($termBox)
    $clausePanel.Children.Add($removeBtn)
    # Add to panel
    $AdditionalFiltersPanel.Children.Add($clausePanel)
})
