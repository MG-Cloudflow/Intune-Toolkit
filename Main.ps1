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

$currentVersion = "v0.3.0.0"

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
        [string]$file = "Main.ps1"
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
        [xml]$xaml = Get-Content $xamlPath -ErrorAction Stop
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
        $ExportToCSVButton = $Window.FindName("ExportToCSVButton")
        $ExportToMDButton = $Window.FindName("ExportToMDButton")
        $ConfigurationPoliciesButton = $Window.FindName("ConfigurationPoliciesButton")
        $DeviceConfigurationButton = $Window.FindName("DeviceConfigurationButton")
        $ComplianceButton = $Window.FindName("ComplianceButton")
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
        $DeviceCustomAttributeShellScriptsButton = $Window.FindName("DeviceCustomAttributeShellScriptsButton")
        $global:CurrentPolicyType = ""

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
        . .\Scripts\AdminTemplatesButton.ps1
        . .\Scripts\ApplicationsButton.ps1
        . .\Scripts\DeleteAssignmentButton.ps1
        . .\Scripts\AddAssignmentButton.ps1
        . .\Scripts\BackupButton.ps1
        . .\Scripts\RestoreButton.ps1
        . .\Scripts\ExportToCSVButton.ps1
        . .\Scripts\ExportToMDButton.ps1
        . .\Scripts\Show-SelectionDialog.ps1
        . .\Scripts\SearchButton.ps1
        . .\Scripts\RemediationScriptsButton.ps1
        . .\Scripts\RenameButton.ps1
        . .\Scripts\PlatformScriptsButton.ps1
        . .\Scripts\AppConfigButton.ps1
        . .\Scripts\MacosScriptsButton.ps1
        . .\Scripts\IntentsButton.ps1  # endpoint security policy aka intents
        . .\Scripts\CheckVersion.ps1    # Check for the latest version of the toolkit
        . .\Scripts\SecurityBaselineAnalysisButton.ps1
        . .\Scripts\DeviceCustomAttributeShellScriptsButton.ps1

        Check-LatestVersion -currentVersion $currentVersion
        Write-IntuneToolkitLog "Successfully imported external scripts"

        # ---------------------------
        # Set the custom icon
        # ---------------------------
        Set-WindowIcon -Window $Window

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
