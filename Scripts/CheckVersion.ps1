<#
.SYNOPSIS
Checks the current running version against the latest release version on GitHub.

.DESCRIPTION
This script retrieves the latest release version from GitHub and compares it with the current running version. If a newer version is available, it notifies the user.

.NOTES
Author: Maxime Guillemin | CloudFlow
Date: 09/07/2024
#>

function Check-LatestVersion {
    param (
        [string]$currentVersion,
        [string]$repoUrl = "https://api.github.com/repos/MG-Cloudflow/Intune-Toolkit/releases/latest"
    )

    try {
        Write-IntuneToolkitLog "Checking for latest version at $repoUrl" -component "Check-LatestVersion" -file "CheckVersion.ps1"
        $response = Invoke-RestMethod -Uri $repoUrl -Method Get
        $latestVersion = $response.tag_name

        if ($latestVersion -ne $currentVersion) {
            $message = "A new version ($latestVersion) is available. You are currently running version $currentVersion. Download the latest Version from github https://github.com/MG-Cloudflow/Intune-Toolkit"
            [System.Windows.Forms.MessageBox]::Show($message, "Update Available", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            Write-IntuneToolkitLog $message -component "Check-LatestVersion" -file "CheckVersion.ps1"
        } else {
            Write-IntuneToolkitLog "You are running the latest version ($currentVersion)" -component "Check-LatestVersion" -file "CheckVersion.ps1"
        }
    } catch {
        $errorMessage = "Failed to check for the latest version. Error: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-IntuneToolkitLog $errorMessage -component "Check-LatestVersion" -file "CheckVersion.ps1"
    }
}

# Example usage:
# Check-LatestVersion -currentVersion "0.2.7"