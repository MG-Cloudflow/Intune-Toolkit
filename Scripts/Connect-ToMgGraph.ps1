<#PSScriptInfo
.VERSION 1.0.1
.GUID
.AUTHOR Thiago Beier forked authentication method from Andrew S Taylor Microsoft MVP
.COMPANYNAME
.COPYRIGHT GPL
.TAGS intune endpoint MEM autopilot
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
v1.0.1 - Added prerequisites check, added devicecode and interactive logon parameters
#>

<#
.SYNOPSIS
    This script connects to Microsoft Graph using different authentication methods, including Interactive, Device Code, App Secret, Certificate Thumbprint, and specific scopes.
    Maxime Guillemin used the script and adapted it for use in Intune-toolkit. All the main logic is by Thiago Beier. Date of change: 15/10/2024

.DESCRIPTION
    This PowerShell script provides three modes of authentication with Microsoft Graph:
    - Scopes only: Connect using a specific set of read-only scopes.
    - App Secret: Authenticate using client credentials (AppId, AppSecret, and Tenant).
    - SSL Certificate: Authenticate using an SSL certificate.

.PARAMETER devicecode
    Executes the script using device code to authenticate. Opens Browser (Default) asks user to authenticate.

.PARAMETER interactive
    Executes the script using interactive only to authenticate. Opens Browser (Default) asks user to authenticate.

.PARAMETER scopesonly
    Executes the script using scopes only to authenticate.

.PARAMETER scopesonly
    Executes the script using scopes only to authenticate.

.PARAMETER entraapp
    Executes the script using App-based authentication with AppId, AppSecret, and Tenant.

.PARAMETER usessl
    Executes the script using certificate-based authentication with AppId, TenantId, and CertificateThumbprint.

.PARAMETER AppId
    The Azure AD Application (client) ID.

.PARAMETER AppSecret
    The client secret for the Azure AD application (required for -entraapp).

.PARAMETER Tenant
    The tenant domain or ID (required for -entraapp).

.PARAMETER TenantId
    The Azure AD Tenant ID (required for -usessl).

.PARAMETER CertificateThumbprint
    The SSL certificate thumbprint (required for -usessl).

.EXAMPLE
    .\script.ps1 -devicecode
    Connects using authenticated user consented scopes/permissions.

.EXAMPLE
    .\script.ps1 -interactive
    Connects using authenticated user consented scopes/permissions.
        
.EXAMPLE
    .\script.ps1 -scopesonly
    Connects using read-only scopes.

.EXAMPLE
    .\script.ps1 -entraapp -AppId "client-id-or-entra-app-id-here" -AppSecret "password-here" -Tenant "your-tenant-domain-here"
    Connects using App-based authentication with client credentials.

.EXAMPLE
    .\script.ps1 -usessl -AppId "client-id-or-entra-app-id-here" -TenantId "your-tenant-id-here" -CertificateThumbprint "your-ssl-certificate-thumbprint-here"
    Connects using certificate-based authentication.

.NOTES
    Author: Thiago Beier (thiago.beier@gmail.com)
	Social: https://x.com/thiagobeier https://thebeier.com/ https://www.linkedin.com/in/tbeier/
    Date: September 11, 2024
#>

param (
    [string]$AppId,
    [string]$TenantId,
    [string]$AppSecret,
    [string]$CertificateThumbprint,
    [string]$Tenant,
    [string[]]$Scopes,  # Array of scopes to be used in authentication
    [switch]$scopesonly, # If true, execute the scopes only block
    [switch]$entraapp, # If true, execute the entra app block
    [switch]$usessl, # If true, execute the SSL certificate block
    [switch]$interactive, # If true, execute the interactive block
    [switch]$devicecode    # If true, execute the device code block
)

#region PowerShell modules and NuGet
# Load the required assembly for GUI popups
#Add-Type -AssemblyName PresentationFramework

# Path to the XAML popup file
$popupXamlFilePath = ".\XML\ModuleInstallPopup.xaml"

# Function to show a WPF confirmation popup window for module installation
function Show-InstallModulePopup {
    param (
        [string]$moduleName
    )

    # Read the XAML from the file
    [xml]$xaml = Get-Content $popupXamlFilePath

    # Create the window from XAML
    $xamlReader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($xamlReader)

    # Dynamically set the message to include the missing module name
    $textBlock = $window.FindName("ModuleInstallMessage")
    $textBlock.Text = "The module '$moduleName' is not installed. Do you want to install it?"

    # Add event handlers for buttons
    $okButton = $window.FindName("OKButton")
    $cancelButton = $window.FindName("CancelButton")

    $okButton.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })

    $cancelButton.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })
    Set-WindowIcon -Window $Window
    # Show the window and return the result
    return $window.ShowDialog()
}


#region PowerShell modules and NuGet
function Install-GraphModules {
    # Define required modules
    $modules = @{
        'Microsoft Graph Authentication' = 'Microsoft.Graph.Authentication'
    }

    foreach ($module in $modules.GetEnumerator()) {
        # Check if the module is already installed
        if (Get-Module -Name $module.value -ListAvailable -ErrorAction SilentlyContinue) {
            Write-IntuneToolkitLog "Module $($module.Value) is already installed." -component "Install-GraphModules" -file "InstallGraphModules.ps1"
        }
        else {
            # Show the install confirmation popup
            $result = Show-InstallModulePopup -moduleName $module.Name

            # If the user clicks OK, proceed with the installation
            if ($result -eq $true) {
                try {
                    # Check if NuGet is installed
                    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                        try {
                            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
                            Write-Host "Installed PackageProvider NuGet"
                            Write-IntuneToolkitLog "Installed PackageProvider NuGet" -component "Install-GraphModules" -file "InstallGraphModules.ps1"
                        }
                        catch {
                            Write-Warning "Error installing provider NuGet, exiting..."
                            Write-IntuneToolkitLog "Error installing provider NuGet, exiting..." -component "Install-GraphModules" -file "InstallGraphModules.ps1"
                            return
                        }
                    }

                    # Set PSGallery as a trusted repository if not already
                    if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
                        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                        Write-IntuneToolkitLog "Set PSGallery as a trusted repository" -component "Install-GraphModules" -file "InstallGraphModules.ps1"
                    }

                    Write-Host ("Installing and importing PowerShell module {0}" -f $module.Value)
                    Install-Module -Name $module.Value -Force -ErrorAction Stop
                    Import-Module -Name $module.Value -ErrorAction Stop
                    Write-IntuneToolkitLog "Successfully installed and imported PowerShell module $($module.Value)" -component "Install-GraphModules" -file "InstallGraphModules.ps1"
                }
                catch {
                    Write-Warning ("Error installing or importing PowerShell module {0}, exiting..." -f $module.Value)
                    Write-IntuneToolkitLog "Error installing or importing PowerShell module $($module.Value), exiting..." -component "Install-GraphModules" -file "InstallGraphModules.ps1"
                    return
                }
            }
            else {
                # If the user cancels, log and close the script
                Write-IntuneToolkitLog "User canceled installation of module $($module.Value)." -component "Install-GraphModules" -file "InstallGraphModules.ps1"
                Exit
            }
        }
    }
}
  
#endregion

# If -entraapp is provided, enforce that AppId, AppSecret, and Tenant are required
if ($entraapp) {
    if (-not $AppId) {
        Write-IntuneToolkitLog "Error: The -AppId parameter is required when using -entraapp." -component "ParameterCheck" -file "ConnectButton.ps1"
        throw "Error: The -AppId parameter is required when using -entraapp."
    }
    if (-not $AppSecret) {
        Write-IntuneToolkitLog "Error: The -AppSecret parameter is required when using -entraapp." -component "ParameterCheck" -file "ConnectButton.ps1"
        throw "Error: The -AppSecret parameter is required when using -entraapp."
    }
    if (-not $Tenant) {
        Write-IntuneToolkitLog "Error: The -Tenant parameter is required when using -entraapp." -component "ParameterCheck" -file "ConnectButton.ps1"
        throw "Error: The -Tenant parameter is required when using -entraapp."
    }
}

# If -usessl is provided, enforce that AppId, TenantId, and CertificateThumbprint are required
if ($usessl) {
    if (-not $AppId) {
        Write-IntuneToolkitLog "Error: The -AppId parameter is required when using -usessl." -component "ParameterCheck" -file "ConnectButton.ps1"
        throw "Error: The -AppId parameter is required when using -usessl."
    }
    if (-not $TenantId) {
        Write-IntuneToolkitLog "Error: The -TenantId parameter is required when using -usessl." -component "ParameterCheck" -file "ConnectButton.ps1"
        throw "Error: The -TenantId parameter is required when using -usessl."
    }
    if (-not $CertificateThumbprint) {
        Write-IntuneToolkitLog "Error: The -CertificateThumbprint parameter is required when using -usessl." -component "ParameterCheck" -file "ConnectButton.ps1"
        throw "Error: The -CertificateThumbprint parameter is required when using -usessl."
    }
}

# Check for -scopesonly parameter
if ($scopesonly) {
    Write-IntuneToolkitLog "Checking NuGet and PowerShell dependencies for -scopesonly parameter" -component "ScopesOnly" -file "ConnectButton.ps1"
    Install-GraphModules

    # region scopesReadOnly ask for authentication
    $scopesReadOnly = @(
        "Chat.ReadWrite.All"
        "Directory.Read.All"
        "Group.Read.All"
    )
    
    try {
        Connect-MgGraph -Scopes $scopesReadOnly -ErrorAction Stop
        Write-IntuneToolkitLog "Successfully connected to Microsoft Graph using scopes only" -component "ScopesOnly" -file "ConnectButton.ps1"
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        Write-IntuneToolkitLog "Error connecting to Microsoft Graph using scopes only, exiting..." -component "ScopesOnly" -file "ConnectButton.ps1"
        return
    }
    # endregion
}

# Check for -entraapp parameter
if ($entraapp) {
    Write-IntuneToolkitLog "Checking NuGet and PowerShell dependencies for -entraapp parameter" -component "EntraApp" -file "ConnectButton.ps1"
    Install-GraphModules

    # region app secret
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $AppId
        client_secret = $AppSecret
        scope         = "https://graph.microsoft.com/.default"
    }

    $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body
    $accessToken = $response.access_token
    $version = (Get-Module microsoft.graph.authentication | Select-Object -ExpandProperty Version).Major

    if ($version -eq 2) {
        $accesstokenfinal = ConvertTo-SecureString -String $accessToken -AsPlainText -Force
    } else {
        Select-MgProfile -Name Beta
        $accesstokenfinal = $accessToken
    }

    try {
        Connect-MgGraph -AccessToken $accesstokenfinal -ErrorAction Stop
        Write-IntuneToolkitLog "Successfully connected to tenant $Tenant using app-based authentication" -component "EntraApp" -file "ConnectButton.ps1"
        Write-Host "Connected to tenant $Tenant using app-based authentication"
    }
    catch {
        Write-Warning "Error connecting to tenant $Tenant using app-based authentication, exiting..."
        Write-IntuneToolkitLog "Error connecting to tenant $Tenant using app-based authentication, exiting..." -component "EntraApp" -file "ConnectButton.ps1"
        return
    }

    Write-Host "This session current permissions `n" -ForegroundColor cyan
    Get-MgContext | Select-Object -ExpandProperty Scopes
    Write-Host "`n"
    Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
}

# Check for -usessl parameter
if ($usessl) {
    Write-IntuneToolkitLog "Checking NuGet and PowerShell dependencies for -usessl parameter" -component "UseSSL" -file "ConnectButton.ps1"
    Install-GraphModules

    try {
        Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop
        Write-IntuneToolkitLog "Successfully connected to Microsoft Graph using certificate-based authentication" -component "UseSSL" -file "ConnectButton.ps1"
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        Write-IntuneToolkitLog "Error connecting to Microsoft Graph using certificate-based authentication, exiting..." -component "UseSSL" -file "ConnectButton.ps1"
        return
    } 
}

# Check for -interactive parameter
if ($interactive) {
    Write-IntuneToolkitLog "Checking NuGet and PowerShell dependencies for -interactive parameter" -component "Interactive" -file "ConnectButton.ps1"
    Install-GraphModules
    
    try {
        Connect-MgGraph -Scopes $Scopes -ErrorAction Stop
        Write-IntuneToolkitLog "Successfully connected to Microsoft Graph using interactive login with specified scopes" -component "Interactive" -file "ConnectButton.ps1"
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        Write-IntuneToolkitLog "Error connecting to Microsoft Graph using interactive login, exiting..." -component "Interactive" -file "ConnectButton.ps1"
        return
    }
}

# Check for -devicecode parameter
if ($devicecode) {
    Write-IntuneToolkitLog "Checking NuGet and PowerShell dependencies for -devicecode parameter" -component "DeviceCode" -file "ConnectButton.ps1"
    Install-GraphModules

    try {
        Start-Process https://microsoft.com/devicelogin -ErrorAction Stop
        Connect-MgGraph -UseDeviceCode -Scopes $Scopes -ErrorAction Stop
        Write-IntuneToolkitLog "Successfully connected to Microsoft Graph using device code authentication" -component "DeviceCode" -file "ConnectButton.ps1"
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        Write-IntuneToolkitLog "Error connecting to Microsoft Graph using device code authentication, exiting..." -component "DeviceCode" -file "ConnectButton.ps1"
        return
    }
}