
<#
.SYNOPSIS
Licenses a user and adds cloud groups via Microsoft Graph; creates the cloud user if missing.

.DESCRIPTION
- Reads onboarding info from config\last_onboarding.json (Cloud UPN, OfficeType, DisplayName, alias).
- Connects to Microsoft Graph (delegated).
- If the user does not exist in Entra ID:
   - Creates the cloud user by default using the temp password from config\defaultpwd.sec,
     unless overridden via -TempPassword or -UseAutoPassword.
   - In -DryRun, simulates creation so the preview can continue (no throw).
- Sets UsageLocation (required for licensing).
- Assigns Microsoft 365 Business Standard if available (String ID: O365_BUSINESS_PREMIUM).
- Adds to All Employees and either Sensapure Team (HQ) or Production (Warehouse).
- Logs to config\onboarding.log; supports -Verbose output.

.PARAMETER ConfigFile
Path to JSON exported by the AD script. Default: config\last_onboarding.json

.PARAMETER SkuPartNumber
License SKU String ID. Default: O365_BUSINESS_PREMIUM

.PARAMETER SkuId
License GUID (optional). If provided, overrides SkuPartNumber

.PARAMETER UsageLocation
Country code for licensing. Default: US

.PARAMETER TempPassword
Plaintext temp password override for cloud user creation (if needed).

.PARAMETER UseAutoPassword
Generate a random strong temp password for cloud user creation (if needed).

.PARAMETER NoCreateCloud
Do NOT auto-create the cloud user if missing (default behavior is to create).

.PARAMETER DryRun
Preview actions without making changes.
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = 'config\last_onboarding.json',
    [string]$SkuPartNumber = 'O365_BUSINESS_PREMIUM',
    [string]$SkuId,
    [string]$UsageLocation = 'US',
    [string]$TempPassword,
    [switch]$UseAutoPassword,
    [switch]$NoCreateCloud,
    [switch]$DryRun
)

# ----------------- Helpers -----------------

function Get-BaseDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) { return (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) }
    return (Get-Location).Path
}

function Get-ConfigDir {
    $base = Get-BaseDir
    $dir  = Join-Path -Path $base -ChildPath 'config'
    if (-not (Test-Path -Path $dir)) { New-Item -Path $dir -ItemType Directory | Out-Null }
    return $dir
}

# Logging (sanitized)
$Global:OnboardLog = Join-Path (Get-ConfigDir) 'onboarding.log'
function Log {
    param([string]$Message)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Path $Global:OnboardLog -Value "[$stamp] $Message"
    Write-Verbose $Message
}

function Ensure-GraphModule {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        throw 'Microsoft.Graph PowerShell SDK is not installed. Install with: Install-Module Microsoft.Graph'
    }
}

function Connect-GraphSafe {
    $scopes = @('User.ReadWrite.All','Organization.Read.All','Directory.ReadWrite.All','Group.ReadWrite.All')
    Connect-MgGraph -Scopes $scopes -NoWelcome
    Log "Connected to Microsoft Graph."
}

function Resolve-Sku {
    param([string]$SkuPartNumber, [string]$SkuId)
    $skus = Get-MgSubscribedSku -All
    $match = if ($SkuId) { $skus | Where-Object { $_.SkuId -eq $SkuId } } else { $skus | Where-Object { $_.SkuPartNumber -eq $SkuPartNumber } }
    if (-not $match) { throw "SKU not found. PartNumber='$SkuPartNumber' SkuId='$SkuId'" }
    $enabled   = [int]$match.PrepaidUnits.Enabled
    $consumed  = [int]$match.ConsumedUnits
    $available = $enabled - $consumed
    Log "SKU: $($match.SkuPartNumber) Enabled=$enabled Consumed=$consumed Available=$available"
    [PSCustomObject]@{ SkuId = $match.SkuId; PartNumber = $match.SkuPartNumber; Available = $available }
}

function New-TempPassword {
    param([int]$Length = 16)
    $upper='ABCDEFGHJKLMNPQRSTUVWXYZ'; $lower='abcdefghijkmnopqrstuvwxyz'; $digits='23456789'; $special='!@#$%^&*()-_=+[]{}'
    $all = ($upper + $lower + $digits + $special).ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object 'System.Byte[]' 4
    $sb = New-Object System.Text.StringBuilder
    for ($i=0; $i -lt $Length; $i++) { $rng.GetBytes($bytes); $idx=[BitConverter]::ToUInt32($bytes,0) % $all.Length; [void]$sb.Append($all[$idx]) }
    $sb.ToString()
}

function Get-DefaultPasswordSecure {
    $file = Join-Path (Get-ConfigDir) 'defaultpwd.sec'
    if (-not (Test-Path $file)) {
        throw "Default password vault not found: $file. Run the AD script once to create it, or pass -TempPassword or -UseAutoPassword."
    }
    $encText = Get-Content -Path $file -Raw -ErrorAction Stop
    ConvertTo-SecureString -String $encText
}

function Get-TempPasswordPlain {
    param([string]$TempPassword,[switch]$UseAutoPassword)
    if ($PSBoundParameters.ContainsKey('TempPassword') -and -not [string]::IsNullOrWhiteSpace($TempPassword)) {
        return $TempPassword
    }
    if ($UseAutoPassword) {
        return (New-TempPassword 16)
    }
    # Default: read from encrypted defaultpwd.sec and convert to plaintext for Graph (in-memory)
    $secure = Get-DefaultPasswordSecure
    $plain  = (New-Object System.Net.NetworkCredential('', $secure)).Password
    if ([string]::IsNullOrWhiteSpace($plain)) { throw "Unable to recover plaintext from default password vault." }
    return $plain
}

function Ensure-UsageLocation {
    param([string]$UserId, [string]$Location)
    $u = Get-MgUser -UserId $UserId -Property Id,UserPrincipalName,UsageLocation
    if (-not $u.UsageLocation) {
        Update-MgUser -UserId $UserId -UsageLocation $Location
        Log "UsageLocation set to $Location for $($u.UserPrincipalName)"
        Write-Host "Set UsageLocation=$Location for $($u.UserPrincipalName)" -ForegroundColor Green
    }
}

function Assign-License-IfAvailable {
    param(
        [Parameter(Mandatory=$true)][string]$UserId,
        [Parameter(Mandatory=$true)][pscustomobject]$SkuInfo  # expects properties: SkuId, PartNumber, Available
    )
    if ($SkuInfo.Available -le 0) {
        Write-Warning "No available licenses for SKU $($SkuInfo.PartNumber). Skipping assignment."
        Log "No available licenses for $($SkuInfo.PartNumber)."
        return $false
    }
    # Assign using the plain SKU GUID
    Set-MgUserLicense -UserId $UserId -AddLicenses @{ SkuId = $SkuInfo.SkuId } -RemoveLicenses @()
    Write-Host "Assigned license $($SkuInfo.PartNumber) to user." -ForegroundColor Green
    Log "License assigned: $($SkuInfo.PartNumber)"
    return $true
}

function Get-GroupByMail {
    param([string]$MailAddress)
    $g = Get-MgGroup -Filter "mail eq '$MailAddress'" -Property Id,DisplayName,Mail,GroupTypes,SecurityEnabled,MailEnabled
    if (-not $g) { throw "Group with mail '$MailAddress' not found." }
    Log "Group resolved: $($g.DisplayName) <$($g.Mail)> (Types=$($g.GroupTypes -join ','), MailEnabled=$($g.MailEnabled), SecurityEnabled=$($g.SecurityEnabled))"
    return $g
}


function Add-User-To-Group {
    param(
        [Parameter(Mandatory=$true)]$Group,         # full group object from Get-GroupByMail
        [Parameter(Mandatory=$true)][string]$UserId,    # Directory object Id
        [Parameter(Mandatory=$true)][string]$UserUPN    # for nicer messages
    )

    $isUnified  = $Group.GroupTypes -and ($Group.GroupTypes -contains 'Unified')
    $isSecurity = [bool]$Group.SecurityEnabled
    $isMailOnly = ($Group.MailEnabled -eq $true) -and ($isSecurity -eq $false) -and (-not $isUnified)  # DL

    if ($isMailOnly) {
        # Distribution List (DL) or mail-enabled-only group => use ExchangeOnline if available
        if (Get-Module -ListAvailable -Name ExchangeOnlineManagement) {
            try {
                if (-not (Get-ConnectionInformation)) {
                    Connect-ExchangeOnline -ShowBanner:$false | Out-Null
                }
            } catch {
                Write-Warning "Could not connect to Exchange Online for DL update: $($_.Exception.Message)"
                Log "EXO connect failed: $($_.Exception.Message)"
                return
            }

            try {
                # Use the group's primary mail and the user's UPN for membership
                Add-DistributionGroupMember -Identity $Group.Mail -Member $UserUPN -ErrorAction Stop
                Write-Host "Added $UserUPN to '$($Group.DisplayName)' <$($Group.Mail)> (Exchange DL)" -ForegroundColor Green
                Log "Added $UserUPN to DL $($Group.DisplayName) <$($Group.Mail)>"
            } catch {
                Write-Warning "Failed to add $UserUPN to DL '$($Group.DisplayName)' <$($Group.Mail)>: $($_.Exception.Message)"
                Log "Add DL member failed: $($_.Exception.Message)"
            }
            return
        } else {
            Write-Warning "Group '$($Group.DisplayName)' is a mail-enabled distribution list. Install ExchangeOnlineManagement and sign in to add members (Add-DistributionGroupMember). Skipping."
            Log "Skipped DL membership for $($Group.DisplayName) <$($Group.Mail)> (EXO not available)."
            return
        }
    }

    # Graph-supported group (Unified or Security)
    try {
        New-MgGroupMember -GroupId $Group.Id -BodyParameter @{ "@odata.id"="https://graph.microsoft.com/v1.0/directoryObjects/$UserId"} -ErrorAction Stop | Out-Null
        Write-Host "Added $UserUPN to '$($Group.DisplayName)' <$($Group.Mail)>" -ForegroundColor Green
        Log "Added member: $UserUPN -> $($Group.DisplayName) <$($Group.Mail)>"
    } catch {
        Write-Warning "Failed to add $UserUPN to '$($Group.DisplayName)' <$($Group.Mail)>: $($_.Exception.Message)"
        Log "Add member failed: $($_.Exception.Message)"
    }
}


# ----------------- Execution -----------------

try { Ensure-GraphModule } catch { Write-Error $_.Exception.Message; return }

# Load onboarding info
if (-not (Test-Path $ConfigFile)) { throw "Config file not found: $ConfigFile" }
$info = Get-Content $ConfigFile -Raw | ConvertFrom-Json

$CloudUPN     = $info.CloudUserPrincipalName
$OfficeType   = $info.OfficeType
$DisplayName  = $info.DisplayName
$MailNickname = $info.CloudMailNickname

if ([string]::IsNullOrWhiteSpace($CloudUPN)) { throw "CloudUserPrincipalName missing in $ConfigFile." }

Log "Starting M365 onboarding for $CloudUPN (OfficeType=$OfficeType)"
Connect-GraphSafe

# Find cloud user
$user = $null
try { $user = Get-MgUser -UserId $CloudUPN -Property Id,DisplayName,UserPrincipalName,Mail } catch { $user = $null }

# Create if missing (default behavior unless -NoCreateCloud)
if (-not $user -and -not $NoCreateCloud) {
    if ($DryRun) {
        Write-Warning "DryRun  would create cloud user '$CloudUPN'."
        Log "DryRun: would create cloud user $CloudUPN"
        # Simulate so the rest of DryRun preview can continue
        $user = [PSCustomObject]@{ Id = 'DRYRUN'; UserPrincipalName = $CloudUPN }
    } else {
        $plainPwd = Get-TempPasswordPlain -TempPassword $TempPassword -UseAutoPassword:$UseAutoPassword
        $body = @{
            accountEnabled    = $true
            displayName       = $DisplayName
            mailNickname      = $MailNickname
            userPrincipalName = $CloudUPN
            passwordProfile   = @{
                forceChangePasswordNextSignIn = $true
                password = $plainPwd
            }
        }
        New-MgUser -BodyParameter $body | Out-Null
        Write-Host "Created cloud user $CloudUPN." -ForegroundColor Green
        Log "Cloud user created: $CloudUPN"
        $user = Get-MgUser -UserId $CloudUPN -Property Id,DisplayName,UserPrincipalName,Mail
        Write-Host "Temporary password (provide securely to the new hire): $plainPwd" -ForegroundColor Yellow
        Log "Temp password used for cloud user (not written to log)."
    }
}

# If still not found, stop
if (-not $user) {
    throw "User '$CloudUPN' not found in Entra ID and auto-create disabled. Re-run without -NoCreateCloud or verify the user."
}

# Resolve SKU and groups
$skuInfo = Resolve-Sku -SkuPartNumber $SkuPartNumber -SkuId $SkuId
Write-Host "License SKU: $($skuInfo.PartNumber) | Available=$($skuInfo.Available)" -ForegroundColor Cyan

$grpAll = Get-GroupByMail 'AllEmployees@sensapureflavors.com'
$grpHQ  = Get-GroupByMail 'sensapureteam@sensapureflavors.com'
$grpWH  = Get-GroupByMail 'production@sensapure.com'

# DryRun preview
if ($DryRun) {
    Write-Warning "DryRun  no changes will be made."
    Write-Host "Would process user: $CloudUPN | OfficeType=$OfficeType" -ForegroundColor Yellow
    Log "DryRun: would set UsageLocation=$UsageLocation, assign $($skuInfo.PartNumber) if available, and add group memberships."
    return
}

# UsageLocation required before licensing
Ensure-UsageLocation -UserId $user.Id -Location $UsageLocation

# Assign license if available
$null = Assign-License-IfAvailable -UserId $user.Id -SkuId $skuInfo

# Add to groups
Add-User-To-Group -Group $grpAll -UserId $user.Id -UserUPN $user.UserPrincipalName
if ($OfficeType -eq 'HQ') {
    Add-User-To-Group -Group $grpHQ -UserId $user.Id -UserUPN $user.UserPrincipalName
} elseif ($OfficeType -eq 'Warehouse') {
    Add-User-To-Group -Group $grpWH -UserId $user.Id -UserUPN $user.UserPrincipalName
}

Write-Host "Cloud onboarding completed for $($user.UserPrincipalName)." -ForegroundColor Green
Log "M365 onboarding complete for $($user.UserPrincipalName)"

