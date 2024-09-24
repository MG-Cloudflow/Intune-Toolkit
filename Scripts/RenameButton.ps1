# Function to fetch policy details with dynamic $select query based on policy type
function Get-PolicyDetails {
    param (
        [string]$policyId
    )

    # Define the $select query based on the current policy type
    $select = switch ($global:CurrentPolicyType) {
        "configurationPolicies" { "id,name,description" }
        default { "id,displayName,description" }
    }

    # Define the URL to fetch policy data based on the current policy type
    if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
        $urlGetPolicy = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$policyId')?`$select=$($select)"
    }
    else {
        $urlGetPolicy = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$policyId')?`$select=$($select)"
    }

    Write-IntuneToolkitLog "Fetching policy details from: $urlGetPolicy" -component "Get-PolicyDetails"
    
    try {
        # Fetch policy details
        $policyDetails = Invoke-MgGraphRequest -Uri $urlGetPolicy -Method GET
        Write-IntuneToolkitLog "Successfully fetched policy details: $($policyDetails | ConvertTo-Json)" -component "Get-PolicyDetails"
        return $policyDetails
    } catch {
        $errorMessage = "Failed to fetch policy details: $($_.Exception.Message)"
        Write-IntuneToolkitLog $errorMessage -component "Get-PolicyDetails"
        throw $errorMessage
    }
}

# Function to show the Rename Popup with prefilled existing name and description
function Show-RenamePopup {
    param (
        [string]$currentName,
        [string]$currentDescription
    )

    $xamlPath = ".\XML\RenamePopup.xaml"

    if (-not (Test-Path $xamlPath)) {
        Write-IntuneToolkitLog "XAML file not found: $xamlPath" -component "RenamePopup"
        return $null
    }

    [xml]$xaml = Get-Content $xamlPath
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    $RenameButton = $Window.FindName("RenameButton")
    $NewPolicyNameTextBox = $Window.FindName("NewPolicyNameTextBox")
    $NewPolicyDescriptionTextBox = $Window.FindName("NewPolicyDescriptionTextBox")

    # Pre-fill the existing policy name and description in the text boxes
    $NewPolicyNameTextBox.Text = $currentName
    $NewPolicyDescriptionTextBox.Text = $currentDescription

    # Declare the new policy name and description as script-level variables to store them after the window closes
    $script:newPolicyName = $null
    $script:newPolicyDescription = $null

    $RenameButton.Add_Click({
        $script:newPolicyName = $NewPolicyNameTextBox.Text.Trim()
        $script:newPolicyDescription = $NewPolicyDescriptionTextBox.Text.Trim()
        if ($script:newPolicyName -and $script:newPolicyDescription) {
            Write-IntuneToolkitLog "New name entered: $script:newPolicyName, New description entered: $script:newPolicyDescription" -component "RenamePopup"
            $Window.Close()
        } else {
            [System.Windows.MessageBox]::Show("Please enter both a valid name and description.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    })

    $Window.ShowDialog() | Out-Null
    return @{Name=$script:newPolicyName; Description=$script:newPolicyDescription}
}

# Main Rename Button Logic (Updated)
$RenameButton.Add_Click({
    Write-IntuneToolkitLog "RenameButton clicked" -component "Rename-Button" -file "RenameButton.ps1"

    try {
        $selectedPolicies = $PolicyDataGrid.SelectedItems
        if ($selectedPolicies.Count -eq 1) {
            $selectedPolicy = $selectedPolicies[0]
            $policyId = $selectedPolicy.PolicyId

            Write-IntuneToolkitLog "Selected policy: $($selectedPolicy | ConvertTo-Json)" -component "Rename-Button"

            # Get detailed info for the selected policy
            $policyDetails = Get-PolicyDetails -policyId $policyId
            Write-IntuneToolkitLog "Fetched policy details: $($policyDetails | ConvertTo-Json)" -component "Rename-Button"

            # Determine which property holds the current name and description based on policy type
            $currentName = switch ($global:CurrentPolicyType) {
                "configurationPolicies" { $policyDetails.name }
                default { $policyDetails.displayName }
            }
            $currentDescription = $policyDetails.description

            # Show the custom XML-based popup with the current name and description prefilled
            $newPolicyInfo = Show-RenamePopup -currentName $currentName -currentDescription $currentDescription

            if ($newPolicyInfo.Name -and $newPolicyInfo.Description -and ($newPolicyInfo.Name -ne $currentName -or $newPolicyInfo.Description -ne $currentDescription)) {
                # Modify the correct property (name or displayName) and description
                $propertyToUpdate = switch ($global:CurrentPolicyType) {
                    "configurationPolicies" { "name" }
                    default { "displayName" }
                }

                # Update the policy details
                $policyDetails.$propertyToUpdate = $newPolicyInfo.Name
                $policyDetails.description = $newPolicyInfo.Description

                # Convert the updated policy details to JSON (including all fields)
                $body = $policyDetails | ConvertTo-Json

                # Log the updated body
                Write-IntuneToolkitLog "Sending PATCH request with updated body: $($body)" -component "Rename-Button"

                # Construct the PATCH URL
                if ($global:CurrentPolicyType -eq "mobileApps" -or $global:CurrentPolicyType -eq "mobileAppConfigurations") {
                    $urlRename = "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')"
                }
                else {
                    $urlRename = "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')"
                }

                try {
                    # Send the PATCH request to rename and update description
                    Invoke-MgGraphRequest -Uri $urlRename -Method PATCH -Body $body -ContentType "application/json"
                    Write-IntuneToolkitLog "Renamed policy/application and updated description: $($selectedPolicy.PolicyId)" -component "Rename-Button" -file "RenameButton.ps1"
                } catch {
                    $errorMessage = "$urlRename Failed to rename policy/application or update description: $($_.Exception.Message)"
                    Write-IntuneToolkitLog $errorMessage -component "Rename-Button"
                    [System.Windows.MessageBox]::Show($errorMessage, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                }

                # Refresh the DataGrid after renaming and updating description
                Load-PolicyData -policyType $global:CurrentPolicyType -loadingMessage "Loading $($global:CurrentPolicyType)..." -loadedMessage "$($global:CurrentPolicyType) loaded."
            } else {
                [System.Windows.MessageBox]::Show("No changes made or same name/description entered.")
            }
        } else {
            [System.Windows.MessageBox]::Show("Please select exactly one policy/application.")
        }
    } catch {
        $errorMessage = "Failed to rename policy/application. Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($errorMessage, "Error")
        Write-IntuneToolkitLog $errorMessage -component "Rename-Button" -file "RenameButton.ps1"
    }
})
