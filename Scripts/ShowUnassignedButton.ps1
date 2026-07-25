<#
.SYNOPSIS
Handles the ShowUnassignedButton toggle to show only items that have no assignments.

.DESCRIPTION
This script wires the "Show Unassigned" toggle button. When checked, the PolicyDataGrid is
filtered to the items in $global:AllPolicyData that have no assignment (an empty
GroupDisplayname), which is how unassigned policies/applications are represented after loading
(see Load-PolicyData / Process-Assignment in Functions.ps1). When unchecked, the full, unfiltered
list is restored. This makes it easy to find, for example, applications that are not assigned to
any group. Requested in issue #63.

.NOTES
Author: Intune Toolkit contributors
Date: 2026-07-24

.EXAMPLE
$ShowUnassignedButton.Add_Checked({
    # Code to handle toggle
})
#>

# Show only items with no assignment (empty GroupDisplayname).
$ShowUnassignedButton.Add_Checked({
    try {
        Write-IntuneToolkitLog "ShowUnassignedButton checked" -component "ShowUnassigned-Button" -file "ShowUnassignedButton.ps1"

        if ($null -eq $global:AllPolicyData) {
            Write-IntuneToolkitLog "No policy data loaded; nothing to filter" -component "ShowUnassigned-Button" -file "ShowUnassignedButton.ps1"
            return
        }

        $unassigned = @(
            $global:AllPolicyData | Where-Object {
                ([string]::IsNullOrWhiteSpace($_.AssignmentType) -or $_.AssignmentType -eq "Not Assigned") -and
                [string]::IsNullOrWhiteSpace($_.GroupDisplayname)
            }
        )
        $PolicyDataGrid.ItemsSource = $unassigned
        $PolicyDataGrid.Items.Refresh()

        Write-IntuneToolkitLog "Showing $($unassigned.Count) item(s) with no assignment" -component "ShowUnassigned-Button" -file "ShowUnassignedButton.ps1"
    } catch {
        $errorMessage = "Failed to show unassigned items. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "ShowUnassigned-Button" -file "ShowUnassignedButton.ps1"
    }
})

# Restore the full, unfiltered list.
$ShowUnassignedButton.Add_Unchecked({
    try {
        Write-IntuneToolkitLog "ShowUnassignedButton unchecked" -component "ShowUnassigned-Button" -file "ShowUnassignedButton.ps1"

        $PolicyDataGrid.ItemsSource = @($global:AllPolicyData)
        $PolicyDataGrid.Items.Refresh()

        Write-IntuneToolkitLog "Restored full policy list" -component "ShowUnassigned-Button" -file "ShowUnassignedButton.ps1"
    } catch {
        $errorMessage = "Failed to restore full list. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "ShowUnassigned-Button" -file "ShowUnassignedButton.ps1"
    }
})
