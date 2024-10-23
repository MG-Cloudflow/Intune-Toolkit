# Function to get assignment settings for iOS Store Apps
function Get-IosStoreAppAssignmentSettings {
    param (
        [string]$ODataType,
        [string]$Intent
    )

    Write-IntuneToolkitLog "Get-IosStoreAppAssignmentSettings called with ODataType: $ODataType, Intent: $Intent" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    $settings = @{
        "@odata.type" = "$ODataType" + "AssignmentSettings"
        vpnConfigurationId = $null
        uninstallOnDeviceRemoval = $null
        isRemovable = $null
        preventManagedAppBackup = $null
    }

    if ($Intent -eq "required") {
        $settings.uninstallOnDeviceRemoval = $false
        $settings.isRemovable = $true
    } elseif ($Intent -eq "available" -or $Intent -eq "availableWithoutEnrollment") {
        $settings.uninstallOnDeviceRemoval = $false
    }

    # Optionally log the constructed settings
    Write-IntuneToolkitLog "Settings constructed: $($settings | ConvertTo-Json -Compress)" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    return $settings
}

# Function to get assignment settings for Android Managed Store Apps
function Get-AndroidManagedStoreAppAssignmentSettings {
    param (
        [string]$ODataType
    )

    Write-IntuneToolkitLog "Get-AndroidManagedStoreAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    $settings = @{
        "@odata.type" = "$ODataType" + "AssignmentSettings"
        androidManagedStoreAppTrackIds = @()
        autoUpdateMode = "default"
    }

    # Optionally log the constructed settings
    Write-IntuneToolkitLog "Settings constructed: $($settings | ConvertTo-Json -Compress)" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    return $settings
}

# Function to get assignment settings for WinGet Apps
function Get-WinGetAppAssignmentSettings {
    param (
        [string]$ODataType
    )

    Write-IntuneToolkitLog "Get-WinGetAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    $settings = @{
        '@odata.type' = "$ODataType" + "AssignmentSettings"
        notifications = "showAll"
        installTimeSettings = $null
        restartSettings = $null
    }

    # Optionally log the constructed settings
    Write-IntuneToolkitLog "Settings constructed: $($settings | ConvertTo-Json -Compress)" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    return $settings
}

# Function to get default assignment settings for other apps
function Get-DefaultAppAssignmentSettings {
    param (
        [string]$ODataType
    )

    Write-IntuneToolkitLog "Get-DefaultAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    $settings = @{
        '@odata.type' = "$ODataType" + "AssignmentSettings"
        notifications = "showAll"
        installTimeSettings = $null
        restartSettings = $null
        deliveryOptimizationPriority = "notConfigured"
    }

    # Optionally log the constructed settings
    Write-IntuneToolkitLog "Settings constructed: $($settings | ConvertTo-Json -Compress)" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"

    return $settings
}

# Functions for each application type that currently call the default settings

function Get-AndroidForWorkAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-AndroidForWorkAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-AndroidLobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-AndroidLobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-AndroidStoreAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-AndroidStoreAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-IosLobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-IosLobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-IosVppAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-IosVppAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-MacOSDmgAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-MacOSDmgAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-MacOSLobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-MacOSLobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-MacOSPkgAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-MacOSPkgAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-ManagedAndroidLobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-ManagedAndroidLobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-ManagedIosLobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-ManagedIosLobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-ManagedMobileLobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-ManagedMobileLobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-MicrosoftStoreForBusinessAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-MicrosoftStoreForBusinessAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-Win32LobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-Win32LobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-WindowsAppXAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-WindowsAppXAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-WindowsMobileMSIAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-WindowsMobileMSIAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-WindowsStoreAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-WindowsStoreAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-WindowsUniversalAppXAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-WindowsUniversalAppXAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-WindowsWebAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-WindowsWebAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}
