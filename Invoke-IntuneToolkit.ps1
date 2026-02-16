<#
.SYNOPSIS
Main script to load and display the Intune Toolkit window with a custom icon.

.DESCRIPTION
This script loads a XAML file to define the UI, locates UI elements, imports required external scripts, 
sets the window's icon programmatically using a custom ICO file located in the script's root folder, 
and displays the window. Error handling and logging are implemented to catch and log errors during these processes.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 09/07/2024

.EXAMPLE
Show-Window
Displays the main window of the application.
#>


$currentVersion = "v1.2.0"


#region Log File Setup
# Define the log file path
$global:logFile = "$env:TEMP\IntuneToolkit.log"

# Create a backup of the existing log file with the current date-time, then clear its content
if (Test-Path -Path $global:logFile -ErrorAction SilentlyContinue) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $backupFilePath = Join-Path -Path $env:TEMP -ChildPath "IntuneToolkit-$timestamp.log"
    Copy-Item -Path $global:logFile -Destination $backupFilePath -ErrorAction SilentlyContinue
    Clear-Content -Path $global:logFile -ErrorAction SilentlyContinue
    $logEntry = "Log entry created at $timestamp"
    Add-Content -Path $global:logFile -Value $logEntry
} else {
    # Create new log file if it doesn't exist
    New-Item -Path $global:logFile -ItemType File -Force -ErrorAction SilentlyContinue
    $logEntry = "Log entry created at $timestamp"
    Add-Content -Path $global:logFile -Value $logEntry
}
#endregion

#region Logging Function
function Write-IntuneToolkitLog {
    param (
        [string]$message,
        [string]$component = "Main-IntuneToolkit",
        [string]$context = "",
        [string]$type = "1",
        [string]$thread = [System.Threading.Thread]::CurrentThread.ManagedThreadId,
        [string]$file = "Invoke-IntuneToolkit.ps1"
    )
    $timestamp = Get-Date -Format "HH:mm:ss.fffzzz"
    $date = Get-Date -Format "MM-dd-yyyy"
    $logMessage = "<![LOG[$message]LOG]!><time=\$($timestamp)\ date=\$($date)\ component=\$($component)\ context=\$($context)\ type=\$($type)\ thread=\$($thread)\ file=\$($file)\>"
    Add-Content -Path $logFile -Value $logMessage
}
#endregion

#region Initialize Debug Log File
if (-Not (Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force | Out-Null
} else {
    Add-Content -Path $logFile -Value "`n`n--- Script started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ---`n"
}
#endregion

#region Load Required Assemblies
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName Microsoft.VisualBasic
    Write-IntuneToolkitLog "Successfully loaded required assemblies"
} catch {
    $errorMessage = "Failed to load required assemblies: $($_.Exception.Message)"
    Write-Error $errorMessage
    Write-IntuneToolkitLog $errorMessage
    exit 1
}
#endregion

#region Check PowerShell Version
$PScurrentVersion = $PSVersionTable.PSVersion
$PSrequiredVersion = [Version]"7.0.0"

if ($PScurrentVersion -lt $PSrequiredVersion) {
    $errorMessage = "You are running PowerShell version $PScurrentVersion. Please upgrade to PowerShell 7 or higher."
    [System.Windows.Forms.MessageBox]::Show($errorMessage, "PowerShell Version outdated", `
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    Write-IntuneToolkitLog $errorMessage
    exit 1
} else {
    Write-IntuneToolkitLog "PowerShell version check passed: $PScurrentVersion"
}
#endregion

#region Main Window Function
function Show-Window {
    Write-IntuneToolkitLog "Starting Show-Window"
    try {
        # ---------------------------
        # Load the XAML file
        # ---------------------------
        $xamlPath = ".\XML\Main.xaml"
        if (-Not (Test-Path $xamlPath)) {
            throw "XAML file not found: $xamlPath"
        }
        Write-IntuneToolkitLog "Loading XAML file from $xamlPath"
        [xml]$xaml = Get-Content $xamlPath -Raw -ErrorAction Stop
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $Window = [Windows.Markup.XamlReader]::Load($reader)
        Write-IntuneToolkitLog "Successfully loaded XAML file"

        # ---------------------------
        # Load UI Elements
        # ---------------------------
        $TenantInfo = $Window.FindName("TenantInfo")
        $ToolkitVersion = $Window.FindName("ToolkitVersion")
        $StatusText = $Window.FindName("StatusText")
        $ConnectButton = $Window.FindName("ConnectButton")
        $ConnectEnterpriseAppButton = $Window.FindName("ConnectEnterpriseAppButton")
        $LogoutButton = $Window.FindName("LogoutButton")
        $RefreshButton = $Window.FindName("RefreshButton")
        $PolicyDataGrid = $Window.FindName("PolicyDataGrid")
        $RenameButton = $Window.FindName("RenameButton")
        $DeleteAssignmentButton = $Window.FindName("DeleteAssignmentButton")
        $AddAssignmentButton = $Window.FindName("AddAssignmentButton")
        $BackupButton = $Window.FindName("BackupButton")
        $RestoreButton = $Window.FindName("RestoreButton")
        # Removed individual export buttons; using unified AssignmentReportButton
        $ConfigurationPoliciesButton = $Window.FindName("ConfigurationPoliciesButton")
        $DeviceConfigurationButton = $Window.FindName("DeviceConfigurationButton")
        $ComplianceButton = $Window.FindName("ComplianceButton")
        $AutopilotProfilesButton = $Window.FindName("AutopilotProfilesButton")
        $AdminTemplatesButton = $Window.FindName("AdminTemplatesButton")
        $IntentsButton = $Window.FindName("IntentsButton")
        $ApplicationsButton = $Window.FindName("ApplicationsButton")
        $AppConfigButton = $Window.FindName("AppConfigButton")
        $RemediationScriptsButton = $Window.FindName("RemediationScriptsButton")
        $PlatformScriptsButton = $Window.FindName("PlatformScriptsButton")
        $MacosScriptsButton = $Window.FindName("MacosScriptsButton")
        $SearchBox = $Window.FindName("SearchBox")
        $SearchButton = $Window.FindName("SearchButton")
        $SearchFieldComboBox = $Window.FindName("SearchFieldComboBox")
        $SecurityBaselineAnalysisButton = $Window.FindName("SecurityBaselineAnalysisButton")
        $SettingsReportButton = $Window.FindName("SettingsReportButton")
        $AdminTemplateReportButton = $Window.FindName("AdminTemplateReportButton")
        $AdminTemplateBaselineComparisonButton = $Window.FindName("AdminTemplateBaselineComparisonButton")
        $DeviceCustomAttributeShellScriptsButton = $Window.FindName("DeviceCustomAttributeShellScriptsButton")
        $AddFilterButton = $Window.FindName("AddFilterButton")
        $AdditionalFiltersPanel = $Window.FindName("AdditionalFiltersPanel")
        
        # New Advanced Actions
        $AdvancedActionsCheckBox = $Window.FindName("AdvancedActionsCheckBox")
        $DeletePolicyButton = $Window.FindName("DeletePolicyButton")
        
        # New Global Search Elements
        $GlobalGroupSearchButton = $Window.FindName("GlobalGroupSearchButton")
        $GlobalSearchProgressBar = $Window.FindName("GlobalSearchProgressBar")

        # Add filter clause logic sourced from external script
        
        # Unified export button
        $AssignmentReportButton = $Window.FindName("AssignmentReportButton")
        # Sidebar context toggles: only one can be selected
        $sidebarButtons = @(
            $GlobalGroupSearchButton,
            $ConfigurationPoliciesButton,
            $DeviceConfigurationButton,
            $ComplianceButton,
            $AutopilotProfilesButton,
            $AdminTemplatesButton,
            $IntentsButton,
            $ApplicationsButton,
            $AppConfigButton,
            $PlatformScriptsButton,
            $RemediationScriptsButton,
            $MacosScriptsButton,
            $DeviceCustomAttributeShellScriptsButton
        )
        foreach ($btn in $sidebarButtons) {
            $btn.Add_Checked({ param($sender, $e)
                foreach ($other in $sidebarButtons) { if ($other -ne $sender) { $other.IsChecked = $false } }
            })
        }
        # Mode toggles for Actions and Reports
        $ActionsToggle = $Window.FindName("ActionsToggle")
        $ReportsToggle = $Window.FindName("ReportsToggle")
        # Ensure mutual exclusivity
        $ActionsToggle.Add_Click({
            $ActionsToggle.IsChecked = $true
            $ReportsToggle.IsChecked = $false
        })
        $ReportsToggle.Add_Click({
            $ReportsToggle.IsChecked = $true
            $ActionsToggle.IsChecked = $false
        })

        # Show/hide bottom action/report buttons
        $actionButtons = @(
            $RenameButton,
            $DeleteAssignmentButton,
            $AddAssignmentButton,
            $BackupButton,
            $RestoreButton,
            $AdvancedActionsCheckBox
        )
        $reportButtons = @(
            $SecurityBaselineAnalysisButton,
            $SettingsReportButton,
            $AdminTemplateReportButton,
            $AdminTemplateBaselineComparisonButton,
            $AssignmentReportButton
        )
        function Set-BottomButtons {
            param([bool]$showActions)
            foreach ($btn in $actionButtons) { 
                $btn.Visibility = if ($showActions) { 'Visible' } else { 'Collapsed' }
                # Grey out action buttons if in Global Search Mode
                if ($global:IsGlobalSearchMode) {
                    $btn.IsEnabled = $false
                } else {
                    $btn.IsEnabled = $true
                }
            }
            foreach ($btn in $reportButtons) { $btn.Visibility = if ($showActions) { 'Collapsed' } else { 'Visible' } }
            
            # Show/hide report buttons based on policy type
            if (-not $showActions) {
                $isAdminTemplates = ($global:CurrentPolicyType -eq "groupPolicyConfigurations")
                $isConfigPolicies = ($global:CurrentPolicyType -eq "configurationPolicies")
                
                # Settings Catalog buttons (only for configurationPolicies)
                $SecurityBaselineAnalysisButton.Visibility = if ($isConfigPolicies) { 'Visible' } else { 'Collapsed' }
                $SettingsReportButton.Visibility = if ($isConfigPolicies) { 'Visible' } else { 'Collapsed' }
                
                # Admin Template buttons (only for groupPolicyConfigurations)
                $AdminTemplateReportButton.Visibility = if ($isAdminTemplates) { 'Visible' } else { 'Collapsed' }
                $AdminTemplateBaselineComparisonButton.Visibility = if ($isAdminTemplates) { 'Visible' } else { 'Collapsed' }
            }
            
            # Special logic for DeletePolicyButton
            if ($showActions -and $AdvancedActionsCheckBox.IsChecked) {
                $DeletePolicyButton.Visibility = 'Visible'
                if ($global:IsGlobalSearchMode) { $DeletePolicyButton.IsEnabled = $false } else { $DeletePolicyButton.IsEnabled = $true }
            } else {
                $DeletePolicyButton.Visibility = 'Collapsed'
            }
        }
        # Initialize with Actions view
        Set-BottomButtons -showActions $true

        # Handle Advanced Actions CheckBox Toggle
        $AdvancedActionsCheckBox.Add_Checked({
             if ($ActionsToggle.IsChecked) { $DeletePolicyButton.Visibility = 'Visible' }
        })
        $AdvancedActionsCheckBox.Add_Unchecked({
             $DeletePolicyButton.Visibility = 'Collapsed'
        })

        # Wire toggles to update visibility
        $ActionsToggle.Add_Click({ Set-BottomButtons -showActions $true })
        $ReportsToggle.Add_Click({ Set-BottomButtons -showActions $false })


        # Import unified report button handler
        #$AssignmentReportButton = $Window.FindName("AssignmentReportButton")
        #. .\Scripts\AssignmentReportButton.ps1

        $global:CurrentPolicyType = ""
        $global:IsGlobalSearchMode = $false

        # ---------------------------
        # Unblock and Import Scripts
        # ---------------------------
        Get-ChildItem -Path ".\Scripts" -Recurse | Unblock-File

        . .\Scripts\Functions.ps1
        . .\Scripts\AssignmentSettingsFunctions.ps1
        . .\Scripts\Connect-ToMgGraph.ps1
        . .\Scripts\ConnectButton.ps1
        . .\Scripts\ConnectEnterpriseAppButton.ps1
        . .\Scripts\LogoutButton.ps1
        . .\Scripts\RefreshButton.ps1
        . .\Scripts\ConfigurationPoliciesButton.ps1
        . .\Scripts\DeviceConfigurationButton.ps1
        . .\Scripts\ComplianceButton.ps1
        . .\Scripts\AutopilotProfilesButton.ps1
        . .\Scripts\AdminTemplatesButton.ps1
        . .\Scripts\ApplicationsButton.ps1
        . .\Scripts\DeleteAssignmentButton.ps1
        . .\Scripts\AddAssignmentButton.ps1
        . .\Scripts\BackupButton.ps1
        . .\Scripts\RestoreButton.ps1
        . .\Scripts\AssignmentReportButton.ps1
        . .\Scripts\DeletePolicyButton.ps1  # New Delete Policy script
        . .\Scripts\Show-SelectionDialog.ps1
        . .\Scripts\SearchButton.ps1
        . .\Scripts\GlobalGroupSearchButton.ps1
        . .\Scripts\Show-GroupSearchDialog.ps1
        . .\Scripts\RemediationScriptsButton.ps1
        . .\Scripts\RenameButton.ps1
        . .\Scripts\PlatformScriptsButton.ps1
        . .\Scripts\AppConfigButton.ps1
        . .\Scripts\MacosScriptsButton.ps1
        . .\Scripts\IntentsButton.ps1  # endpoint security policy aka intents
        . .\Scripts\CheckVersion.ps1    # Check for the latest version of the toolkit
        . .\Scripts\SecurityBaselineAnalysisButton.ps1
        . .\Scripts\DeviceCustomAttributeShellScriptsButton.ps1
        . .\Scripts\SettingsReportButton.ps1
        . .\Scripts\AdminTemplateReportButton.ps1
        . .\Scripts\AdminTemplateBaselineComparisonButton.ps1
        . .\Scripts\AddFilterButton.ps1

        Check-LatestVersion -currentVersion $currentVersion
        Write-IntuneToolkitLog "Successfully imported external scripts"

        # ---------------------------
        # Set the custom icon
        # ---------------------------
        Set-WindowIcon -Window $Window

        # ---------------------------
        # Check for cached Microsoft Graph session
        # ---------------------------
        try {
            # Import Microsoft.Graph.Authentication module to check for cached session
            if (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication) {
                Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
                Write-IntuneToolkitLog "Imported Microsoft.Graph.Authentication module" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
            }
            else {
                Write-IntuneToolkitLog "Microsoft.Graph.Authentication module not installed, skipping cached session check" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
            }

            $context = Get-MgContext -ErrorAction SilentlyContinue
            if ($context -and $context.TenantId) {
                Write-IntuneToolkitLog "Found cached Microsoft Graph session for tenant: $($context.TenantId)" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
                
                # Update UI elements to reflect connected state
                $StatusText.Text = "Please select a policy type."
                $PolicyDataGrid.Visibility = "Visible"
                $RenameButton.IsEnabled = $true
                $DeleteAssignmentButton.IsEnabled = $true
                $AddAssignmentButton.IsEnabled = $true
                $BackupButton.IsEnabled = $true
                $RestoreButton.IsEnabled = $true
                $ConfigurationPoliciesButton.IsEnabled = $true
                $GlobalGroupSearchButton.IsEnabled = $true
                $DeviceConfigurationButton.IsEnabled = $true
                $ComplianceButton.IsEnabled = $true
                $AdminTemplatesButton.IsEnabled = $true
                $ApplicationsButton.IsEnabled = $true
                $AppConfigButton.IsEnabled = $true
                $MacosScriptsButton.IsEnabled = $true
                $IntentsButton.IsEnabled = $true
                $RemediationScriptsButton.IsEnabled = $true
                $PlatformScriptsButton.IsEnabled = $true
                $ConnectButton.IsEnabled = $false
                $ConnectEnterpriseAppButton.IsEnabled = $false
                $LogoutButton.IsEnabled = $true
                $RefreshButton.IsEnabled = $true
                $SearchFieldComboBox.IsEnabled = $true
                $SearchBox.IsEnabled = $true
                $SearchButton.IsEnabled = $true
                $AssignmentReportButton.IsEnabled = $true
                $DeviceCustomAttributeShellScriptsButton.IsEnabled = $true
                $AutopilotProfilesButton.IsEnabled = $true
                $AddFilterButton.IsEnabled = $true

                # Fetch and display tenant information
                try {
                    $tenant = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
                    $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/me" -Method GET
                    $appInfo = if ($context.AppName) { "$($context.AppName) ($($context.ClientId))" } else { $context.ClientId }
                    $TenantInfo.Text = "Tenant: $($tenant.value[0].displayName) | User: $($user.userPrincipalName)`nApp: $appInfo"
                    Write-IntuneToolkitLog "Restored session - Tenant: $($tenant.value[0].displayName), User: $($user.userPrincipalName)" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
                }
                catch {
                    Write-IntuneToolkitLog "Could not fetch tenant details from cached session: $($_.Exception.Message)" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
                    $TenantInfo.Text = "Connected (cached session)"
                }

                # Fetch security groups
                try {
                    Write-IntuneToolkitLog "Fetching security groups from cached session" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
                    $global:AllSecurityGroups = Get-AllSecurityGroups
                    Write-IntuneToolkitLog "Successfully fetched security groups" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
                }
                catch {
                    Write-IntuneToolkitLog "Could not fetch security groups: $($_.Exception.Message)" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
                }
            }
            else {
                Write-IntuneToolkitLog "No cached Microsoft Graph session found" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
            }
        }
        catch {
            Write-IntuneToolkitLog "Error checking for cached session: $($_.Exception.Message)" -component "Main-IntuneToolkit" -file "Invoke-IntuneToolkit.ps1"
        }

        # ---------------------------
        # Show the window
        # ---------------------------
        $ToolkitVersion.Text = "Version: $currentVersion"
        $Window.ShowDialog() | Out-Null
        Write-IntuneToolkitLog "Displayed the window successfully"
    } catch {
        $errorMessage = "Failed to load and display the window: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage
    }
}
#endregion

# Show the window
Show-Window
