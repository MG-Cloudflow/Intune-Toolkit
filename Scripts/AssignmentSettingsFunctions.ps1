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
        autoUpdateMode = "priority"
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
    param (
        [string]$ODataType
    )

    <#
    .NOTES
    For the Android-for-Work app assignment the only settings exposed by the androidManagedStoreAppAssignmentSettings type are:
      - androidManagedStoreAppTrackIds – a collection of strings identifying which Managed Google Play tracks to enable for this assignment (e.g. internal, alpha, beta, production).
      - autoUpdateMode – an enum controlling how updates are prioritized. Possible values are:
          * default (device updates only when on Wi-Fi, charging, and idle)
          * postponed (updates are delayed up to 90 days)
          * priority (app is updated as soon as the developer publishes it)
          * unknownFutureValue (reserved for future use)
    Source: Microsoft Learn :contentReference[oaicite:0]{index=0}
    #>

    # Log invocation
    Write-IntuneToolkitLog "Get-AndroidForWorkAppAssignmentSettings called with ODataType: $ODataType" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    # Build the settings object with sensible defaults
    $settings = @{
        "@odata.type"                   = "$ODataType" + "AssignmentSettings"
        androidManagedStoreAppTrackIds  = @("production")
        autoUpdateMode                  = "priority"
    }

    # Log the constructed settings payload
    Write-IntuneToolkitLog "Settings constructed: $($settings | ConvertTo-Json -Compress)" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    return $settings
}


function Get-AndroidLobAppAssignmentSettings {
    param (
        [string]$ODataType
    )

    <#
    .NOTES
    Android LOB (Line-of-Business) apps do not expose any assignment-settings schema,
    so this function returns $null to produce `"settings": null` in the Graph payload.
    Example payload:

    {
      "mobileAppAssignments": [
        {
          "@odata.type": "#microsoft.graph.mobileAppAssignment",
          "target": {
            "@odata.type": "#microsoft.graph.groupAssignmentTarget",
            "groupId": "1308db11-d833-42df-9d79-8e3aad641cbd"
          },
          "intent": "Required",
          "settings": null
        }
      ]
    }

    Source: example provided by user
    #>

    # Log invocation
    Write-IntuneToolkitLog "Get-AndroidLobAppAssignmentSettings called with ODataType: $ODataType" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    return $null
}


function Get-AndroidStoreAppAssignmentSettings {
    param (
        [string]$ODataType
    )

    <#
    .NOTES
    Android Store apps do not expose any assignment‐settings schema,
    so this function always returns $null to produce `"settings": null`
    in the Graph payload, e.g.:

      {
        "@odata.type": "#microsoft.graph.mobileAppAssignment",
        "target": {
          "@odata.type": "#microsoft.graph.groupAssignmentTarget",
          "groupId": "be15d590-30cb-410d-a855-ece936cee847"
        },
        "intent": "Required",
        "settings": null
      }

    Source: your example payload
    #>

    # Log invocation
    Write-IntuneToolkitLog "Get-AndroidStoreAppAssignmentSettings called with ODataType: $ODataType" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    return $null
}


function Get-IosLobAppAssignmentSettings {
    param (
        [string]$ODataType,
        [string]$Intent
    )

    <#
    .NOTES
    iOS LOB apps use the same assignment-settings schema as iOS Store apps:
      – vpnConfigurationId
      – uninstallOnDeviceRemoval
      – isRemovable
      – preventManagedAppBackup

    Example payload for a Required assignment:
    {
      "mobileAppAssignments":[
        {
          "@odata.type":"#microsoft.graph.mobileAppAssignment",
          "target":{ … },
          "intent":"Required",
          "settings":{
            "@odata.type":"#microsoft.graph.iosLobAppAssignmentSettings",
            "vpnConfigurationId":null,
            "uninstallOnDeviceRemoval":true,
            "isRemovable":true,
            "preventManagedAppBackup":false
          }
        }
      ]
    }
    Source: example provided by user
    #>

    # Log invocation
    Write-IntuneToolkitLog "Get-IosLobAppAssignmentSettings called with ODataType: $ODataType, Intent: $Intent" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    # Base structure with all four fields
    $settings = @{
        "@odata.type"               = "$ODataType" + "AssignmentSettings"
        vpnConfigurationId          = $null
        uninstallOnDeviceRemoval    = $null
        isRemovable                 = $null
        preventManagedAppBackup     = $null
    }

    # Populate based on intent
    if ($Intent -eq "Required") {
        $settings.uninstallOnDeviceRemoval = $true
        $settings.isRemovable              = $true
        $settings.preventManagedAppBackup  = $false
    }
    elseif ($Intent -in @("Available","availableWithoutEnrollment")) {
        $settings.uninstallOnDeviceRemoval = $false
        # isRemovable and preventManagedAppBackup stay null
    }

    # Log constructed settings
    Write-IntuneToolkitLog "Settings constructed: $($settings | ConvertTo-Json -Compress)" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    return $settings
}


function Get-IosVppAppAssignmentSettings {
    param (
        [string]$ODataType,
        [string]$Intent
    )

    <#
    .NOTES
    iOS VPP (Volume Purchase Program) apps expose the following assignment‐settings schema:

    | Property                   | Type     | Description                                                                               | Example Values        |
    | -------------------------- | -------- | ----------------------------------------------------------------------------------------- | --------------------- |
    | vpnConfigurationId         | String?  | (Optional) The Intune-managed VPN configuration to apply to this app.                     | $null or "abc-123"    |
    | useDeviceLicensing         | Boolean  | If $true, the app uses device-based VPP licensing; if $false, user-based licensing.      | $true / $false        |
    | uninstallOnDeviceRemoval   | Boolean  | If $true, the app is uninstalled when the device is removed from Intune.                 | $true / $false        |
    | isRemovable                | Boolean  | If $true, end users can manually uninstall the app; if $false, they cannot.              | $true / $false        |
    | preventManagedAppBackup    | Boolean  | If $true, app data is blocked from iCloud backup.                                         | $true / $false        |
    | preventAutoAppUpdate       | Boolean  | If $true, iOS will not auto‐update the app even when updates exist in the VPP store.     | $true / $false        |

    Example payload for a Required assignment:
    {
      "mobileAppAssignments": [
        {
          "@odata.type":"#microsoft.graph.mobileAppAssignment",
          "intent":"required",
          "target": { … },
          "settings": {
            "@odata.type":"#microsoft.graph.iosVppAppAssignmentSettings",
            "vpnConfigurationId": null,
            "useDeviceLicensing": true,
            "uninstallOnDeviceRemoval": false,
            "isRemovable": true,
            "preventManagedAppBackup": false,
            "preventAutoAppUpdate": false
          }
        }
      ]
    }
    Source: example payload provided by user
    #>

    # Log invocation
    Write-IntuneToolkitLog "Get-IosVppAppAssignmentSettings called with ODataType: $ODataType, Intent: $Intent" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    # Initialize all properties to $null
    $settings = @{
        "@odata.type"               = "$ODataType" + "AssignmentSettings"
        vpnConfigurationId          = $null
        useDeviceLicensing          = $null
        uninstallOnDeviceRemoval    = $null
        isRemovable                 = $null
        preventManagedAppBackup     = $null
        preventAutoAppUpdate        = $null
    }

    # Populate defaults for a Required intent
    if ($Intent -eq "required") {
        $settings.useDeviceLicensing       = $true
        $settings.uninstallOnDeviceRemoval = $false
        $settings.isRemovable              = $true
        $settings.preventManagedAppBackup  = $false
        $settings.preventAutoAppUpdate     = $false
    }
    elseif ($Intent -in @("Available","availableWithoutEnrollment")) {
        $settings.uninstallOnDeviceRemoval = $false
        $settings.useDeviceLicensing       = $true
        $settings.preventManagedAppBackup  = $false
        $settings.preventAutoAppUpdate     = $false
    }

    # Log the constructed settings payload
    Write-IntuneToolkitLog "Settings constructed: $($settings | ConvertTo-Json -Compress)" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    return $settings
}


function Get-MacOSDmgAppAssignmentSettings {
    param (
        [string]$ODataType
    )

    <#
    .NOTES
    macOS DMG apps do not expose any assignment‐settings schema,
    so this function always returns $null to produce `"settings": null`
    in the Graph payload. Example payload:

      {
        "@odata.type": "#microsoft.graph.mobileAppAssignment",
        "target": {
          "@odata.type": "#microsoft.graph.groupAssignmentTarget",
          "groupId": "01234567-89ab-cdef-0123-456789abcdef"
        },
        "intent": "Required",
        "settings": null
      }

    Source: aligned with AndroidStoreApp example
    #>

    # Log invocation
    Write-IntuneToolkitLog "Get-MacOSPkgAppAssignmentSettings called with ODataType: $ODataType" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    return $null
}

function Get-MacOSLobAppAssignmentSettings {
    param ([string]$ODataType)
    Write-IntuneToolkitLog "Get-MacOSLobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
    return Get-DefaultAppAssignmentSettings -ODataType $ODataType
}

function Get-MacOSPkgAppAssignmentSettings {
    param (
        [string]$ODataType
    )

    <#
    .NOTES
    macOS PKG apps do not expose any assignment‐settings schema,
    so this function always returns $null to produce `"settings": null`
    in the Graph payload. Example payload:

      {
        "@odata.type": "#microsoft.graph.mobileAppAssignment",
        "target": {
          "@odata.type": "#microsoft.graph.groupAssignmentTarget",
          "groupId": "01234567-89ab-cdef-0123-456789abcdef"
        },
        "intent": "Required",
        "settings": null
      }
    #>

    # Log invocation
    Write-IntuneToolkitLog "Get-MacOSPkgAppAssignmentSettings called with ODataType: $ODataType" `
        -component "AssignmentSettingsFunctions" `
        -file "AssignmentSettingsFunctions.ps1"

    return $null
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
    param (
        [string]$ODataType,
        [string]$notifications = "showAll",
        [string]$deliveryOptimizationPriority = "notConfigured"
    )
    Write-IntuneToolkitLog "Get-Win32LobAppAssignmentSettings called with ODataType: $ODataType" -component "AssignmentSettingsFunctions" -file "AssignmentSettingsFunctions.ps1"
        $settings = @{
        '@odata.type' = "$ODataType" + "AssignmentSettings"
        notifications = $notifications
        installTimeSettings = $null
        restartSettings = $null
        deliveryOptimizationPriority = $deliveryOptimizationPriority
        }
    return $settings
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
