<#
.SYNOPSIS
Main script to load and display the Intune Toolkit window.

.DESCRIPTION
This script loads a XAML file to define the UI, locates UI elements,
imports required external scripts, and displays the window. Error handling
and logging are implemented to catch and log errors during these processes.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 21/06/2024

.EXAMPLE
Show-Window
Displays the main window of the application.
#>

# Define the log file path
$logFile = ".\IntuneToolkit.log"

# Function to log actions and errors to the IntuneToolkit log file
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

# Initialize the debug log file
if (-Not (Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force | Out-Null
} else {
    Add-Content -Path $logFile -Value "`n`n--- Script started at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") ---`n"
}

# Load required assemblies with error handling
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

# Function to display the main window
function Show-Window {
    Write-IntuneToolkitLog "Starting Show-Window"
    try {
        $xamlPath = ".\XML\Main.xaml"
        if (-Not (Test-Path $xamlPath)) {
            throw "XAML file not found: $xamlPath"
        }
        Write-IntuneToolkitLog "Loading XAML file from $xamlPath"
        [xml]$xaml = Get-Content $xamlPath -ErrorAction Stop

        $reader = (New-Object System.Xml.XmlNodeReader $xaml)
        $Window = [Windows.Markup.XamlReader]::Load($reader)
        Write-IntuneToolkitLog "Successfully loaded XAML file"

        # Load UI elements
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
        $AdminTemplatesButton = $Window.FindName("AdminTemplatesButton")
        $ApplicationsButton = $Window.FindName("ApplicationsButton")
        $SearchBox = $Window.FindName("SearchBox")
        $SearchButton = $Window.FindName("SearchButton")
        $SearchFieldComboBox = $Window.FindName("SearchFieldComboBox")
        $global:CurrentPolicyType = ""

        Get-ChildItem -Path ".\Scripts" -Recurse | Unblock-File

        # Import external script files
        . .\Scripts\Functions.ps1
        . .\Scripts\ConnectButton.ps1
        . .\Scripts\LogoutButton.ps1
        . .\Scripts\ConfigurationPoliciesButton.ps1
        . .\Scripts\DeviceConfigurationButton.ps1
        . .\Scripts\ComplianceButton.ps1
        . .\Scripts\AdminTemplatesButton.ps1
        . .\Scripts\ApplicationsButton.ps1
        . .\Scripts\DeleteAssignmentButton.ps1
        . .\Scripts\AddAssignmentButton.ps1
        . .\Scripts\BackupButton.ps1
        . .\Scripts\RestoreButton.ps1
        . .\Scripts\Show-SelectionDialog.ps1
        . .\Scripts\SearchButton.ps1

        Write-IntuneToolkitLog "Successfully imported external scripts"

        $Window.ShowDialog() | Out-Null
        Write-IntuneToolkitLog "Displayed the window successfully"
    } catch {
        $errorMessage = "Failed to load and display the window: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage
    }
}

# Show the window
Show-Window
