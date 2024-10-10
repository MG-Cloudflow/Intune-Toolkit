Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

function Show-Window {
    $xamlPath = "C:\Users\MaximeGuillemin\OneDrive - CloudFlow\Github\Intune-Assignment-Assistant\XML\PolicyManagement.xaml"
    [xml]$xaml = Get-Content $xamlPath

    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    $TenantInfo = $Window.FindName("TenantInfo")
    $ConnectButton = $Window.FindName("ConnectButton")
    $LogoutButton = $Window.FindName("LogoutButton")
    $StatusText = $Window.FindName("StatusText")
    $PolicyDataGrid = $Window.FindName("PolicyDataGrid")
    $DeleteAssignmentButton = $Window.FindName("DeleteAssignmentButton")
    $AddAssignmentButton = $Window.FindName("AddAssignmentButton")
    $BackupButton = $Window.FindName("BackupButton")
    $RestoreButton = $Window.FindName("RestoreButton")
    $ConfigurationPoliciesButton = $Window.FindName("ConfigurationPoliciesButton")
    $DeviceConfigurationButton = $Window.FindName("DeviceConfigurationButton")
    $ComplianceButton = $Window.FindName("ComplianceButton")

    $ConnectButton.Add_Click({
        try {
            # Connect to Microsoft Graph
            Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "DeviceManagementConfiguration.ReadWrite.All"
            [System.Windows.MessageBox]::Show("Connected to Microsoft Graph.", "Success")

            # Get tenant information
            $tenant = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
            $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/me" -Method GET

            # Display tenant name and signed-in user
            $TenantInfo.Text = "Tenant: $($tenant.value[0].displayName) - Signed in as: $($user.userPrincipalName)"

            # Update UI elements
            $StatusText.Text = "Please select a policy type."
            $PolicyDataGrid.Visibility = "Visible"
            $DeleteAssignmentButton.IsEnabled = $true
            $AddAssignmentButton.IsEnabled = $true
            $BackupButton.IsEnabled = $true
            $RestoreButton.IsEnabled = $true
            $ConfigurationPoliciesButton.IsEnabled = $true
            $DeviceConfigurationButton.IsEnabled = $true
            $ComplianceButton.IsEnabled = $true
            $ConnectButton.Visibility = "Hidden"
            $LogoutButton.Visibility = "Visible"
        } catch {
            [System.Windows.MessageBox]::Show("Failed to connect to Microsoft Graph. Please try again. Error: $_", "Error")
        }
    })

    $LogoutButton.Add_Click({
        try {
            Disconnect-MgGraph
            [System.Windows.MessageBox]::Show("Disconnected from Microsoft Graph.", "Success")

            # Reset UI elements
            $TenantInfo.Text = ""
            $StatusText.Text = "Please login to Graph before using the app"
            $PolicyDataGrid.Visibility = "Hidden"
            $DeleteAssignmentButton.IsEnabled = $false
            $AddAssignmentButton.IsEnabled = $false
            $BackupButton.IsEnabled = $false
            $RestoreButton.IsEnabled = $false
            $ConfigurationPoliciesButton.IsEnabled = $false
            $DeviceConfigurationButton.IsEnabled = $false
            $ComplianceButton.IsEnabled = $false
            $ConnectButton.Visibility = "Visible"
            $LogoutButton.Visibility = "Hidden"
        } catch {
            [System.Windows.MessageBox]::Show("Failed to disconnect from Microsoft Graph. Please try again. Error: $_", "Error")
        }
    })

    $ConfigurationPoliciesButton.Add_Click({
        $StatusText.Text = "Loading configuration policies..."
        $pollicyassignments = Reload-Grid -type "configurationPolicies"
        $PolicyDataGrid.ItemsSource = $pollicyassignments
        $StatusText.Text = "Configuration policies loaded."
    })

    $DeviceConfigurationButton.Add_Click({
        $StatusText.Text = "Loading device configurations..."
        $pollicyassignments = Reload-Grid -type "deviceConfigurations"
        $PolicyDataGrid.ItemsSource = $pollicyassignments
        $StatusText.Text = "Device configurations loaded."
    })

    $ComplianceButton.Add_Click({
        $StatusText.Text = "Loading compliance policies..."
        $pollicyassignments = Reload-Grid -type "deviceCompliancePolicies"
        $PolicyDataGrid.ItemsSource = $pollicyassignments
        $StatusText.Text = "Compliance policies loaded."
    })

    # Delete assignment button click event
    $DeleteAssignmentButton.Add_Click({
        $selectedPolicy = $PolicyDataGrid.SelectedItem
        if ($selectedPolicy) {
            # Get current assignments
            $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($selectedPolicy.PolicyId)')/assignments"
            $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value

            # Filter out the selected group
            $updatedAssignments = @()
            foreach ($assignment in $assignments) {
                if ($assignment.target.groupId -ne $selectedPolicy.GroupId) {
                    $assignmentObject = @{
                        target = @{
                            '@odata.type' = "#microsoft.graph.groupAssignmentTarget"
                            groupId = $assignment.target.groupId
                            deviceAndAppManagementAssignmentFilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                            deviceAndAppManagementAssignmentFilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                        }
                    }
                    $updatedAssignments += $assignmentObject
                }
            }

            # Create the body object
            $bodyObject = @{
                assignments = $updatedAssignments
            }

            # Convert the body object to a JSON string
            $body = $bodyObject | ConvertTo-Json -Depth 10

            # Show the selected group ID and the body in a popup text box
            $message = "Selected Group ID: $($selectedPolicy.GroupId)`n`nNew Assignments Body:`n$body"
            [System.Windows.MessageBox]::Show($message, "New Assignments Body")

            # Update the assignments
            $UrlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($selectedPolicy.PolicyId)')/assign"
            Invoke-MgGraphRequest -Uri $UrlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
            [System.Windows.MessageBox]::Show("Assignment updated.")

            # Refresh the DataGrid after deletion
            $pollicyassignments = Reload-Grid -type "configurationPolicies"
            $PolicyDataGrid.ItemsSource = $pollicyassignments
        } else {
            [System.Windows.MessageBox]::Show("Please select a policy.")
        }
    })

    # Add assignment button click event
    $AddAssignmentButton.Add_Click({
        $selectedPolicy = $PolicyDataGrid.SelectedItem
        if ($selectedPolicy) {
            # Get all security groups and allow selection
            $allGroups = Get-AllSecurityGroups
            $selectedGroup = $allGroups | Out-GridView -Title "Select a Group to Add" -PassThru
            if ($selectedGroup) {
                # Get current assignments
                $urlGetAssignments = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($selectedPolicy.PolicyId)')/assignments"
                $assignments = (Invoke-MgGraphRequest -Uri $urlGetAssignments -Method GET).value

                # Add the new group to the assignments
                $newAssignment = @{
                    target = @{
                        '@odata.type' = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $selectedGroup.Id
                        deviceAndAppManagementAssignmentFilterId = $null
                        deviceAndAppManagementAssignmentFilterType = "none"
                    }
                }
                $assignments += $newAssignment

                # Create the body object
                $bodyObject = @{
                    assignments = $assignments
                }

                # Convert the body object to a JSON string
                $body = $bodyObject | ConvertTo-Json -Depth 10

                # Show the selected group ID and the body in a popup text box
                $message = "Selected Group ID: $($selectedGroup.Id)`n`nNew Assignments Body:`n$body"
                [System.Windows.MessageBox]::Show($message, "New Assignments Body")

                # Update the assignments
                $UrlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($selectedPolicy.PolicyId)')/assign"
                Invoke-MgGraphRequest -Uri $UrlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
                [System.Windows.MessageBox]::Show("Assignment updated.")

                # Refresh the DataGrid after adding assignment
                $pollicyassignments = Reload-Grid -type "configurationPolicies"
                $PolicyDataGrid.ItemsSource = $pollicyassignments
            } else {
                [System.Windows.MessageBox]::Show("No group selected.")
            }
        } else {
            [System.Windows.MessageBox]::Show("Please select a policy.")
        }
    })

    # Backup button click event
    $BackupButton.Add_Click({
        $backup = Get-GraphData -url "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=settings,assignments"
        $jsonBackup = $backup | ConvertTo-Json -Depth 20

        # Save file dialog
        $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $SaveFileDialog.Filter = "JSON files (*.json)|*.json"
        $SaveFileDialog.Title = "Save Backup As"
        $SaveFileDialog.ShowDialog() | Out-Null

        if ($SaveFileDialog.FileName -ne "") {
            $jsonBackup | Out-File -FilePath $SaveFileDialog.FileName
            [System.Windows.MessageBox]::Show("Backup saved successfully.", "Success")
        } else {
            [System.Windows.MessageBox]::Show("Backup canceled.", "Information")
        }
    })

    # Restore button click event
    $RestoreButton.Add_Click({
        # Open file dialog to select backup file
        $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $OpenFileDialog.Filter = "JSON files (*.json)|*.json"
        $OpenFileDialog.Title = "Select Backup File"
        $OpenFileDialog.ShowDialog() | Out-Null

        if ($OpenFileDialog.FileName -ne "") {
            # Read and parse the backup file
            $backupContent = Get-Content -Path $OpenFileDialog.FileName -Raw
            $backupData = $backupContent | ConvertFrom-Json

            # Loop through each policy in the backup
            foreach ($policy in $backupData) {
                # Create the assignments body for the policy
                $bodyObject = @{
                    assignments = $policy.assignments
                }

                # Convert the body object to a JSON string
                $body = $bodyObject | ConvertTo-Json -Depth 10

                # Update the assignments for the policy
                $UrlUpdateAssignments = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($policy.id)')/assign"
                Invoke-MgGraphRequest -Uri $UrlUpdateAssignments -Method POST -Body $body -ContentType "application/json"
            }

            [System.Windows.MessageBox]::Show("Assignments restored successfully.", "Success")

            # Refresh the DataGrid after restoration
            $pollicyassignments = Reload-Grid -type "configurationPolicies"
            $PolicyDataGrid.ItemsSource = $pollicyassignments
        } else {
            [System.Windows.MessageBox]::Show("Restore canceled.", "Information")
        }
    })

    $Window.ShowDialog() | Out-Null
}

# Function to get all security groups
function Get-AllSecurityGroups {
    $url = "https://graph.microsoft.com/beta/groups"
    $groups = Invoke-MgGraphRequest -Uri $url -Method GET -Headers @{ 'ConsistencyLevel' = 'eventual' }
    return $groups.value | Select-Object Id, DisplayName
}

# Function to get data from Graph API with pagination
function Get-GraphData {
    param (
        [Parameter(Mandatory=$true)]
        [string] $url
    )
    $results = @()
    do {
        $response = Invoke-MgGraphRequest -Uri $url -Method GET
        if ($response.'@odata.nextLink' -ne $null) {
            $url = $response.'@odata.nextLink'
            $results += $response.value
        } else {
            $results += $response.Value
            return $results
        }
    } while ($response.'@odata.nextLink')
}

# Function to reload the grid data
function Reload-Grid {
    param (
        [Parameter(Mandatory=$true)]
        [string] $type
    )
    $url = "https://graph.microsoft.com/beta/deviceManagement/$($type)?`$expand=assignments"
    $result = Get-GraphData -url $url

    # Load policies into the DataGrid
    $pollicyassignments = @()
    foreach ($pollicy in $result) {
        if ($type -eq "deviceConfigurations") {
            if ($null -ne $pollicy.assignments -and $pollicy.assignments.Count -gt 0) {
                foreach ($assignment in $pollicy.assignments) {
                    $filter = $null
                    $group = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/$($assignment.target.groupId)" -Method GET)
                    $filter = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($assignment.target.deviceAndAppManagementAssignmentFilterId)" -Method GET)
                    $pollicyassignments += [PSCustomObject]@{
                        PolicyId = $pollicy.id
                        PolicyName = $pollicy.displayName
                        PolicyDescription = $pollicy.description
                        PolicyPlatforms = $pollicy.'@odata.type'
                        GroupDisplayname = $group.displayName
                        GroupId = $assignment.target.groupId
                        FilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        FilterDisplayname = $filter.displayName
                        FilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                    }
                }
            } else {
                $pollicyassignments += [PSCustomObject]@{
                    PolicyId = $pollicy.id
                    PolicyName = $pollicy.displayName
                    PolicyDescription = $pollicy.description
                    PolicyPlatforms = $pollicy.platforms
                    GroupDisplayname = ""
                    GroupId = ""
                    FilterId = ""
                    FilterDisplayname = ""
                    FilterType = ""
                }
            }
        } elseif ($type -eq "configurationPolicies") {
            if ($null -ne $pollicy.assignments -and $pollicy.assignments.Count -gt 0) {
                foreach ($assignment in $pollicy.assignments) {
                    $group = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/$($assignment.target.groupId)" -Method GET)
                    $filter = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($assignment.target.deviceAndAppManagementAssignmentFilterId)" -Method GET)
                    $pollicyassignments += [PSCustomObject]@{
                        PolicyId = $pollicy.id
                        PolicyName = $pollicy.name
                        PolicyDescription = $pollicy.description
                        PolicyPlatforms = $pollicy.platforms
                        GroupDisplayname = $group.displayName
                        GroupId = $assignment.target.groupId
                        FilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        FilterDisplayname = $filter.displayName
                        FilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                    }
                }
            } else {
                $pollicyassignments += [PSCustomObject]@{
                    PolicyId = $pollicy.id
                    PolicyName = $pollicy.name
                    PolicyDescription = $pollicy.description
                    PolicyPlatforms = $pollicy.platforms
                    GroupDisplayname = ""
                    GroupId = ""
                    FilterId = ""
                    FilterDisplayname = ""
                    FilterType = ""
                }
            }
        } elseif ($type -eq "deviceCompliancePolicies") {
            if ($null -ne $pollicy.assignments -and $pollicy.assignments.Count -gt 0) {
                foreach ($assignment in $pollicy.assignments) {
                    $group = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/$($assignment.target.groupId)" -Method GET)
                    $filter = (Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($assignment.target.deviceAndAppManagementAssignmentFilterId)" -Method GET)
                    $pollicyassignments += [PSCustomObject]@{
                        PolicyId = $pollicy.id
                        PolicyName = $pollicy.displayName
                        PolicyDescription = $pollicy.description
                        PolicyPlatforms = $pollicy.'@odata.type'
                        GroupDisplayname = $group.displayName
                        GroupId = $assignment.target.groupId
                        FilterId = $assignment.target.deviceAndAppManagementAssignmentFilterId
                        FilterDisplayname = $filter.displayName
                        FilterType = $assignment.target.deviceAndAppManagementAssignmentFilterType
                    }
                }
            } else {
                $pollicyassignments += [PSCustomObject]@{
                    PolicyId = $pollicy.id
                    PolicyName = $pollicy.displayName
                    PolicyDescription = $pollicy.description
                    PolicyPlatforms = $pollicy.platforms
                    GroupDisplayname = ""
                    GroupId = ""
                    FilterId = ""
                    FilterDisplayname = ""
                    FilterType = ""
                }
            }
        }
    }
    return $pollicyassignments
}

# Show the window
Show-Window
