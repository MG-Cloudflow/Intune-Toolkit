<#
.SYNOPSIS
Handles the renaming and updating of descriptions for selected policies in the Intune Toolkit.

.DESCRIPTION
This script allows users to rename and update the descriptions of selected policies or applications 
in the Intune Toolkit. It fetches current policy details, displays a custom popup with the 
existing name and description prefilled, and processes the renaming and updating actions. 
The script includes error handling, logging, and a refresh of the DataGrid after the updates.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 20/09/2024

.EXAMPLE
$RenameButton.Add_Click({
    $selectedPolicies = $PolicyDataGrid.SelectedItems
    if ($selectedPolicies.Count -eq 1) {
        # Process renaming and description update
    } else {
        [System.Windows.MessageBox]::Show("Please select exactly one policy/application.")
    }
})
#>


# Fetches policy details using a dynamic $select query based on the current policy type
function Get-PolicyDetails {
    param (
        [string]$policyId
    )

    # Determine the fields to select for the given policy type
    $select = switch ($global:CurrentPolicyType) {
        "configurationPolicies" { "id,name,description" }
        default { "id,displayName,description" }
    }

    # Construct the URL for the Graph API call based on the policy type
    $urlGetPolicy = if ($global:CurrentPolicyType -in @("mobileApps", "mobileAppConfigurations")) {
        "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$policyId')?`$select=$($select)"
    } else {
        "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$policyId')?`$select=$($select)"
    }

    Write-IntuneToolkitLog "Fetching policy details from: $urlGetPolicy" -component "Get-PolicyDetails"
    
    try {
        # Fetch the policy details from Microsoft Graph API
        $policyDetails = Invoke-MgGraphRequest -Uri $urlGetPolicy -Method GET
        #Write-IntuneToolkitLog "Successfully fetched policy details: $($policyDetails | ConvertTo-Json)" -component "Get-PolicyDetails"
        return $policyDetails
    } catch {
        $errorMessage = "Failed to fetch policy details: $($_.Exception.Message)"
        Write-IntuneToolkitLog $errorMessage -component "Get-PolicyDetails"
        throw $errorMessage
    }
}

# Displays the Rename Popup with the current policy name and description prefilled
function Show-RenamePopup {
    param (
        [string]$currentName,
        [string]$currentDescription
    )

    # Path to the XAML file for the Rename Popup UI
    $xamlPath = ".\XML\RenamePopup.xaml"

    # Verify if the XAML file exists
    if (-not (Test-Path $xamlPath)) {
        Write-IntuneToolkitLog "XAML file not found: $xamlPath" -component "RenamePopup"
        return $null
    }

    # Load the XAML content
    [xml]$xaml = Get-Content $xamlPath
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    # Assign controls from the XAML to variables
    $RenameButton = $Window.FindName("RenameButton")
    $NewPolicyNameTextBox = $Window.FindName("NewPolicyNameTextBox")
    $NewPolicyDescriptionTextBox = $Window.FindName("NewPolicyDescriptionTextBox")

    # Pre-fill the text boxes with current name and description
    $NewPolicyNameTextBox.Text = $currentName
    $NewPolicyDescriptionTextBox.Text = $currentDescription

    # Initialize script-level variables to store new policy details
    $script:newPolicyName = $null
    $script:newPolicyDescription = $null

    # Define the action for the Rename button click
    $RenameButton.Add_Click({
        $script:newPolicyName = $NewPolicyNameTextBox.Text.Trim()
        $script:newPolicyDescription = $NewPolicyDescriptionTextBox.Text.Trim()
        if ($script:newPolicyName -and $script:newPolicyDescription) {
            Write-IntuneToolkitLog "New name: $script:newPolicyName, New description: $script:newPolicyDescription" -component "RenamePopup"
            $Window.Close()
        } else {
            [System.Windows.MessageBox]::Show("Please enter both a valid name and description.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    })
    Set-WindowIcon -Window $Window
    # Display the Rename Popup window
    $Window.ShowDialog() | Out-Null
    return @{Name=$script:newPolicyName; Description=$script:newPolicyDescription}
}

# Logic for the Rename Button click event
$RenameButton.Add_Click({
    Write-IntuneToolkitLog "RenameButton clicked" -component "Rename-Button" -file "RenameButton.ps1"

    try {
        # Ensure only one policy is selected
        $selectedPolicies = $PolicyDataGrid.SelectedItems
        if ($selectedPolicies.Count -eq 1) {
            $selectedPolicy = $selectedPolicies[0]
            $policyId = $selectedPolicy.PolicyId

            Write-IntuneToolkitLog "Selected policy: $($selectedPolicy | ConvertTo-Json)" -component "Rename-Button"

            # Fetch detailed policy information
            $policyDetails = Get-PolicyDetails -policyId $policyId
            Write-IntuneToolkitLog "Fetched policy details: $($policyDetails | ConvertTo-Json)" -component "Rename-Button"

            # Determine the correct property for the policy name based on policy type
            $currentName = switch ($global:CurrentPolicyType) {
                "configurationPolicies" { $policyDetails.name }
                default { $policyDetails.displayName }
            }
            $currentDescription = $policyDetails.description

            # Display the Rename Popup with current name and description prefilled
            $newPolicyInfo = Show-RenamePopup -currentName $currentName -currentDescription $currentDescription

            # Proceed if there are valid changes to the name or description
            if ($newPolicyInfo.Name -and $newPolicyInfo.Description -and ($newPolicyInfo.Name -ne $currentName -or $newPolicyInfo.Description -ne $currentDescription)) {
                # Determine the property to update (name or displayName)
                $propertyToUpdate = switch ($global:CurrentPolicyType) {
                    "configurationPolicies" { "name" }
                    default { "displayName" }
                }

                # Update the policy details with the new name and description
                $policyDetails.$propertyToUpdate = $newPolicyInfo.Name
                $policyDetails.description = $newPolicyInfo.Description

                # Convert the updated policy details to JSON format
                $body = $policyDetails | ConvertTo-Json

                Write-IntuneToolkitLog "Sending PATCH request with updated body: $($body)" -component "Rename-Button"

                # Construct the PATCH URL for renaming
                $urlRename = if ($global:CurrentPolicyType -in @("mobileApps", "mobileAppConfigurations")) {
                    "https://graph.microsoft.com/beta/deviceAppManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')"
                } else {
                    "https://graph.microsoft.com/beta/deviceManagement/$($global:CurrentPolicyType)('$($selectedPolicy.PolicyId)')"
                }

                try {
                    # Send the PATCH request to update the policy name and description
                    Invoke-MgGraphRequest -Uri $urlRename -Method PATCH -Body $body -ContentType "application/json"
                    Write-IntuneToolkitLog "Renamed policy/application and updated description: $($selectedPolicy.PolicyId)" -component "Rename-Button" -file "RenameButton.ps1"
                } catch {
                    $errorMessage = "Failed to rename or update description: $($_.Exception.Message)"
                    Write-IntuneToolkitLog $errorMessage -component "Rename-Button"
                    [System.Windows.MessageBox]::Show($errorMessage, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                }

                # Refresh the DataGrid to reflect the changes
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
