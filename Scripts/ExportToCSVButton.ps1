<#
.SYNOPSIS
Handles the click event for the ExportToCSVButton to export data displayed in the grid to a CSV file.

.DESCRIPTION
This script is triggered when the ExportToCSVButton is clicked. It exports the data displayed in the grid to a CSV file. It includes a file save dialog for the user to choose the file location and name, as well as logging for each major step and error handling.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 03/07/2024

.EXAMPLE
$ExportToCSVButton.Add_Click({
    # Code to handle click event
})
#>

$ExportToCSVButton.Add_Click({
    Write-IntuneToolkitLog "ExportToCSVButton clicked" -component "ExportToCSV-Button" -file "ExportToCSVButton.ps1"

    try {
        # Open file save dialog
        $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $SaveFileDialog.Filter = "CSV files (*.csv)|*.csv"
        $SaveFileDialog.Title = "Save CSV As"
        $SaveFileDialog.ShowDialog() | Out-Null

        if ($SaveFileDialog.FileName -ne "") {
            $csvFilePath = $SaveFileDialog.FileName

            # Export the data to CSV
            $global:AllPolicyData | Export-Csv -Path $csvFilePath -NoTypeInformation
            [System.Windows.MessageBox]::Show("Data exported to CSV successfully.", "Success")
            Write-IntuneToolkitLog "Data exported to CSV at: $csvFilePath" -component "ExportToCSV-Button" -file "ExportToCSVButton.ps1"
        } else {
            [System.Windows.MessageBox]::Show("Export canceled.", "Information")
            Write-IntuneToolkitLog "Export canceled by user." -component "ExportToCSV-Button" -file "ExportToCSVButton.ps1"
        }
    } catch {
        $errorMessage = "Failed to export data to CSV. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "ExportToCSV-Button" -file "ExportToCSVButton.ps1"
    }
})
