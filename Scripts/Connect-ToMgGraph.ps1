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
function Install-GraphModules {
    #Get NuGet
    if (-not (Get-PackageProvider NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force:$true | Out-Null
            Write-Host "Installed PackageProvider NuGet"
        }
        catch {
            Write-Warning "Error installing provider NuGet, exiting..."
            return
        }
    }

    #Get Graph Authentication modules (and dependencies)
    $modules = @{
        'Microsoft Graph Authentication' = 'Microsoft.Graph.Authentication'
        'MS Graph Groups'                = 'Microsoft.Graph.Groups'
        'MS Graph Identity Management'   = 'Microsoft.Graph.Identity.DirectoryManagement'
        'MS Graph Users'                 = 'Microsoft.Graph.Users'
    }

    #Set PSGallery as Trusted
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    foreach ($module in $modules.GetEnumerator()) {
        if (Get-Module -Name $module.value -ListAvailable -ErrorAction SilentlyContinue) {
            Import-Module -Name $module.value
        }
        else {
            try {
                Install-Module $module.Value -ErrorAction Stop
                Write-Host ("Installing and importing PowerShell module {0}" -f $module.value) -ErrorAction Stop
                Import-Module -Name $module.value -ErrorAction Stop
            }
            catch {
                Write-Warning ("Error Installing or importing Powershell module {0}, exiting..." -f $module.value)
                return
            }
        }
    }
}     

#endregion

#If -entraapp is provided, enforce that AppId, AppSecret, and Tenant are required
if ($entraapp) {
    #Call the function
    #Write-Host "Checking NuGet and PowerShell dependencies `n" -ForegroundColor cyan
    #Install-GraphModules

    if (-not $AppId) {
        throw "Error: The -AppId parameter is required when using -entraapp."
    }
    if (-not $AppSecret) {
        throw "Error: The -AppSecret parameter is required when using -entraapp."
    }
    if (-not $Tenant) {
        throw "Error: The -Tenant parameter is required when using -entraapp."
    }
}

#If -entraapp is provided, enforce that AppId, AppSecret, and Tenant are required
if ($usessl) {
    #Call the function
    Write-Host "Checking NuGet and PowerShell dependencies `n" -ForegroundColor cyan
    Install-GraphModules

    if (-not $AppId) {
        throw "Error: The -AppId parameter is required when using -usessl."
    }
    if (-not $TenantId) {
        throw "Error: The -TenantId parameter is required when using -usessl."
    }
    if (-not $CertificateThumbprint) {
        throw "Error: The -CertificateThumbprint parameter is required when using -usessl."
    }
}

#Check for -scopesonly parameter
if ($scopesonly) {
    #Call the function
    Write-Host "Checking NuGet and PowerShell dependencies `n" -ForegroundColor cyan
    Install-GraphModules

    #region scopesReadOnly ask for authentication
    $scopesReadOnly = @(
        "Chat.ReadWrite.All"
        "Directory.Read.All"
        "Group.Read.All"
    )
    
    try {
        Connect-MgGraph -Scopes $scopesReadOnly -ErrorAction Stop
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        return
    }
    #endregion
}

# Check for -entraapp parameter
if ($entraapp) {
    #Call the function
    Write-Host "Checking NuGet and PowerShell dependencies `n" -ForegroundColor cyan
    Install-GraphModules

    #region app secret
    #Populate with the App Registration details and Tenant ID to validate manually
    #$appid = ''
    #$tenantid = ''
    #$appsecret = ''
    $version = (Get-Module microsoft.graph.authentication | Select-Object -ExpandProperty Version).Major
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $AppId
        client_secret = $AppSecret
        scope         = "https://graph.microsoft.com/.default"
    }

    $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body
    $accessToken = $response.access_token
    if ($version -eq 2) {
        Write-Host "Version 2 module detected"
        $accesstokenfinal = ConvertTo-SecureString -String $accessToken -AsPlainText -Force
    }
    else {
        Write-Host "Version 1 Module Detected"
        Select-MgProfile -Name Beta
        $accesstokenfinal = $accessToken
    }

    try {
        Connect-MgGraph -AccessToken $accesstokenfinal -ErrorAction Stop
        Write-Host "Connected to tenant $Tenant using app-based authentication"
    }
    catch {
        Write-Warning "Error connecting to tenant $Tenant using app-based authentication, exiting..."
        return
    }

    #Get-MgContext
    Write-Host "This session current permissions `n" -ForegroundColor cyan
    Get-MgContext | Select-Object -ExpandProperty Scopes
    Write-Host "`n"
    Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    #Disconnect-MgGraph
    #endregion
}

#Check for -usessl parameter
if ($usessl) {
    #Call the function
    Write-Host "Checking NuGet and PowerShell dependencies `n" -ForegroundColor cyan
    Install-GraphModules

    try {
        #region ssl certificate authentication
        Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop
        #Get-MgContext
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"
        #(Get-MgContext).scopes
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
        #Disconnect-MgGraph
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        return
    } 
    #endregion
}

#Check for -interactive parameter
if ($interactive) {
    #Call the function
    Write-Host "Checking NuGet and PowerShell dependencies `n" -ForegroundColor cyan
    Install-GraphModules
    
    try {
        Connect-MgGraph -Scopes $Scopes -ErrorAction Stop
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"
        #(Get-MgContext).scopes
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        return
    }
}

#Check for -devicecode parameter
if ($devicecode) {
    #Call the function
    Write-Host "Checking NuGet and PowerShell dependencies `n" -ForegroundColor cyan
    Install-GraphModules

    try {
        #Start Browser
        Start-Process https://microsoft.com/devicelogin -ErrorAction Stop

        #Wait for the user to enter the code provided on Screen to authenticate on opened Browser (Default)
        Connect-MgGraph -UseDeviceCode -Scopes $Scopes -ErrorAction Stop
    
        Write-Host "This session current permissions `n" -ForegroundColor cyan
        Get-MgContext | Select-Object -ExpandProperty Scopes -ErrorAction Stop
        Write-Host "`n"

        #(Get-MgContext).scopes
        Write-Host "Please run Disconnect-MgGraph to disconnect `n" -ForegroundColor darkyellow
    }
    catch {
        Write-Warning "Error connecting to Microsoft Graph or user aborted, exiting..."
        return
    }
}