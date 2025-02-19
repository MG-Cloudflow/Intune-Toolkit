# Attach the click event handler to the existing $ConnectEnterpriseAppButton
$ConnectEnterpriseAppButton.Add_Click({

    # Define the path to the external XAML file
    $XAMLPath = ".\XML\EnterpriseAppConnectWindow.xaml"

    # Load the XAML from the file
    if (-not (Test-Path $XAMLPath)) {
        Write-IntuneToolkitLog "XAML file not found at path: $XAMLPath" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"
        $StatusText.Text = "Error: XAML file not found."
        return
    }

    Write-IntuneToolkitLog "Loading XAML from: $XAMLPath" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"

    # Read the XAML content from the file
    [xml]$XAML = Get-Content -Path $XAMLPath

    # Load the XAML and show the window
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$XAML.OuterXml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    Write-IntuneToolkitLog "XAML window loaded successfully" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"

    # Get access to the elements within the window
    $TenantIDTextBox = $window.FindName("TenantIDTextBox")
    $AppIDTextBox = $window.FindName("AppIDTextBox")
    $AppSecretTextBox = $window.FindName("AppSecretTextBox")
    $SubmitButton = $window.FindName("SubmitButton")

    # Define the click event handler for the Submit button
    $SubmitButton.Add_Click({
        # Retrieve values from the textboxes
        $TenantID = $TenantIDTextBox.Text
        $AppID = $AppIDTextBox.Text
        $AppSecret = $AppSecretTextBox.Password

        # Validate inputs
        if (-not $TenantID -or -not $AppID -or -not $AppSecret) {
            Write-IntuneToolkitLog "Failed: Missing input fields (TenantID, AppID, or AppSecret)" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"
            $StatusText.Text = "Error: Please fill out all fields."
            return
        }

        Write-IntuneToolkitLog "User input collected: Tenant ID = $TenantID, App ID = $AppID" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"

        # Close the window once values are captured
        $window.Close()

        # Log the connection attempt
        Write-IntuneToolkitLog "Attempting to connect using Tenant ID: $TenantID, App ID: $AppID" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"
        $StatusText.Text = "Connecting to Microsoft Graph..."

        try {
            # Use the imported Connect-ToMgGraph script to connect with the provided Tenant ID, App ID, and App Secret
            $authParams = @{
                entraapp = $true
                AppId = $AppID
                AppSecret = $AppSecret
                Tenant = $TenantID
                Scopes = @("User.Read.All", "Directory.Read.All", "DeviceManagementConfiguration.ReadWrite.All", "DeviceManagementApps.ReadWrite.All")
            }

            # Call Connect-ToMgGraph.ps1 to authenticate using app credentials
            .\Scripts\Connect-ToMgGraph.ps1 @authParams
            Write-IntuneToolkitLog "Successfully connected to Microsoft Graph with app credentials" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"

            # Update UI elements after successful connection
            Write-IntuneToolkitLog "Updating UI elements after successful connection" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"

            # Update UI elements
            $StatusText.Text = "Please select a policy type."
            $PolicyDataGrid.Visibility = "Visible"
            $RenameButton.IsEnabled = $true
            $DeleteAssignmentButton.IsEnabled = $true
            $AddAssignmentButton.IsEnabled = $true
            $BackupButton.IsEnabled = $true
            $RestoreButton.IsEnabled = $true
            $ConfigurationPoliciesButton.IsEnabled = $true
            $DeviceConfigurationButton.IsEnabled = $true
            $ComplianceButton.IsEnabled = $true
            $AdminTemplatesButton.IsEnabled = $true
            $ApplicationsButton.IsEnabled = $true
            $AppConfigButton.IsEnabled = $true
            $MacosScriptsButton.IsEnabled = $true
            $IntentsButton.IsEnabled = $true
            #$RemediationScriptsButton.IsEnabled = $true
            $PlatformScriptsButton.IsEnabled = $true
            $ConnectButton.IsEnabled = $false
            $ConnectEnterpriseAppButton.IsEnabled = $false
            $LogoutButton.IsEnabled = $true
            $RefreshButton.IsEnabled = $true
            $SearchFieldComboBox.IsEnabled = $true
            $SearchBox.IsEnabled = $true
            $SearchButton.IsEnabled = $true
            $ExportToCSVButton.IsEnabled = $true
            $ExportToMDButton.IsEnabled = $true
            $DeviceCustomAttributeShellScriptsButton.IsEnabled = $true

            Write-IntuneToolkitLog "UI elements updated successfully" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"

        } catch {
            # Handle connection errors
            Write-IntuneToolkitLog "Failed to connect to Microsoft Graph. Error: $($_.Exception.Message)" -component "ConnectEnterpriseAppButton" -file "ConnectEnterpriseAppButton.ps1"
            $StatusText.Text = "Error: Failed to connect to Microsoft Graph. Please try again."
        }
    })
    Set-WindowIcon -Window $Window
    # Show the popup window
    $window.ShowDialog()
})
