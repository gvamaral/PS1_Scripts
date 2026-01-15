
<#
.SYNOPSIS
Creates a new Active Directory user and exports onboarding info to JSON.

.DESCRIPTION
- Prompts for AD admin credentials.
- Collects First/Last Name, Job Title, Department, Start Date.
- Company defaults to "Sensapure" unless -ConfirmNames is provided.
- Sets Description as "Title - mm/dd/yy".
- samAccountName: first initial + last; ensures uniqueness by progressively adding first-name letters.
- Enables account immediately; sets ChangePasswordAtLogon.
- Temp password: auto-generated or manually entered; default stored encrypted (DPAPI) in .\config\defaultpwd.sec.
- Adds user to "SensapureUsers" group.
- Prompts for OfficeType (HQ or Warehouse).
- Exports onboarding info to config\last_onboarding.json, including CloudUserPrincipalName (first.last@sensapure.com).
- Writes a sanitized log to config\onboarding.log.

.PARAMETER Server
AD domain or DC to target. Default: ad.sensapure.com

.PARAMETER DefaultOU
Default OU DN for new users. Default: OU=General,OU=Users,OU=Domain Users,DC=ad,DC=sensapure,DC=com

.PARAMETER UPNSuffix
On-prem AD UPN suffix. Default: ad.sensapure.com

.PARAMETER CloudDomain
Cloud UPN/email domain. Default: sensapure.com

.PARAMETER TempPassword
Override temporary password for this run (plaintext).

.PARAMETER UseAutoPassword
Use auto-generated temporary password for this run.

.PARAMETER ConfirmNames
Prompt to confirm Company, DisplayName, and samAccountName; otherwise use defaults automatically.

.PARAMETER DryRun
Preview actions without creating anything.

.NOTES
Author: Gabriel Amaral (with M365 Copilot)
#>

[CmdletBinding()]
param(
    [string]$Server = 'ad.sensapure.com',
    [string]$DefaultOU = 'OU=General,OU=Users,OU=Domain Users,DC=ad,DC=sensapure,DC=com',
    [string]$UPNSuffix = 'ad.sensapure.com',
    [string]$CloudDomain = 'sensapure.com',
    [string]$TempPassword,
    [switch]$UseAutoPassword,
    [switch]$ConfirmNames,
    [switch]$DryRun
)

# ----------------- Helpers -----------------

function Ensure-ADModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory module is not installed. Install RSAT: Active Directory.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop
}

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

function Get-ADAdminCredential {
    param([string]$Target)
    Write-Host "Enter your AD admin credentials for '$Target'..."
    $cred = Get-Credential -Message "Domain admin credentials for $Target"
    if (-not $cred) { throw 'No credentials provided.' }
    return $cred
}

function Read-NonEmpty { param([string]$Prompt,[string]$Default)
    while ($true) {
        $msg = $Prompt
        if ($PSBoundParameters.ContainsKey('Default') -and -not [string]::IsNullOrWhiteSpace($Default)) { $msg += " (default: $Default)" }
        $val = Read-Host $msg
        if ([string]::IsNullOrWhiteSpace($val)) {
            if ($PSBoundParameters.ContainsKey('Default') -and -not [string]::IsNullOrWhiteSpace($Default)) { return $Default }
            Write-Host 'Value cannot be empty.' -ForegroundColor Yellow
        } else { return $val.Trim() }
    }
}

function Read-Date { param([string]$Prompt)
    $formats = @('MM/dd/yyyy','M/d/yyyy','MM/dd/yy','M/d/yy','yyyy-MM-dd','yyyy/MM/dd')
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    while ($true) {
        $s = Read-Host $Prompt
        $s = $s.Trim()
        if ([string]::IsNullOrWhiteSpace($s)) { Write-Host 'Date cannot be empty.' -ForegroundColor Yellow; continue }
        foreach ($fmt in $formats) { try { return [DateTime]::ParseExact($s,$fmt,$culture) } catch {} }
        try { return [DateTime]::Parse($s,$culture) } catch { Write-Host 'Invalid date. Examples: 12/22/2025, 2025-12-22' -ForegroundColor Yellow }
    }
}

function New-TempPassword { param([int]$Length = 16)
    $upper='ABCDEFGHJKLMNPQRSTUVWXYZ'; $lower='abcdefghijkmnopqrstuvwxyz'; $digits='23456789'; $special='!@#$%^&*()-_=+[]{}'
    $all = ($upper + $lower + $digits + $special).ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object 'System.Byte[]' 4
    $sb = New-Object System.Text.StringBuilder
    for ($i=0; $i -lt $Length; $i++) { $rng.GetBytes($bytes); $idx=[BitConverter]::ToUInt32($bytes,0) % $all.Length; [void]$sb.Append($all[$idx]) }
    $pwd = $sb.ToString().ToCharArray()
    if ($pwd.Length -ge 4) {
        $pwd[0]=$upper[(Get-Random -Minimum 0 -Maximum $upper.Length)]
        $pwd[1]=$lower[(Get-Random -Minimum 0 -Maximum $lower.Length)]
        $pwd[2]=$digits[(Get-Random -Minimum 0 -Maximum $digits.Length)]
        $pwd[3]=$special[(Get-Random -Minimum 0 -Maximum $special.Length)]
    }
    -join $pwd
}

function Choose-OU { param([string]$Server,[pscredential]$Credential,[string]$PreferredDN)
    if ($PreferredDN) {
        try { $ou = Get-ADOrganizationalUnit -Identity $PreferredDN -Server $Server -Credential $Credential -ErrorAction Stop; Write-Host "Using default OU: $($ou.DistinguishedName)" -ForegroundColor Green; return $ou.DistinguishedName }
        catch { Write-Host "Default OU not found or inaccessible: $PreferredDN" -ForegroundColor Yellow }
    }
    Write-Host ''; Write-Host 'Select an OU (or paste a DN):' -ForegroundColor Cyan
    $ous = Get-ADOrganizationalUnit -Filter * -Server $Server -Credential $Credential | Sort-Object -Property DistinguishedName | Select-Object -ExpandProperty DistinguishedName
    for ($i=0; $i -lt $ous.Count; $i++) { Write-Host "[$i] $($ous[$i])" }
    $choice = Read-Host 'Enter index or paste DN'
    if ($choice -match '^\d+$') { $idx=[int]$choice; if ($idx -ge 0 -and $idx -lt $ous.Count) { return $ous[$idx] } throw 'OU index out of range.' }
    else { if ([string]::IsNullOrWhiteSpace($choice)) { throw 'OU DN is required.' } return $choice.Trim() }
}

function Sanitize-NamePart { param([string]$s) ($s -replace '[^a-zA-Z0-9]', '').ToLowerInvariant() }

function Suggest-SamAccountNameBase { param([string]$First,[string]$Last)
    $firstSan=Sanitize-NamePart $First; $lastSan=Sanitize-NamePart $Last
    if ($firstSan.Length -gt 0) { $firstSan.Substring(0,1) + $lastSan } else { $lastSan }
}

function Ensure-UniqueSamProgressive { param([string]$Server,[pscredential]$Credential,[string]$First,[string]$Last)
    $firstSan=Sanitize-NamePart $First; $lastSan=Sanitize-NamePart $Last
    $prefixLen = [Math]::Min(1,[Math]::Max($firstSan.Length,0))
    $candidate = if ($prefixLen -gt 0) { $firstSan.Substring(0,$prefixLen) + $lastSan } else { $lastSan }
    while ($true) {
        $exists=$null; try { $exists=Get-ADUser -Filter "SamAccountName -eq '$candidate'" -Server $Server -Credential $Credential } catch {}
        if (-not $exists) { return $candidate }
        $prefixLen++
        if ($prefixLen -le $firstSan.Length -and $firstSan.Length -gt 0) { $candidate=$firstSan.Substring(0,$prefixLen) + $lastSan; continue }
        $suffix=1
        while ($true) {
            $cand2="$candidate$suffix"
            try { $exists2=Get-ADUser -Filter "SamAccountName -eq '$cand2'" -Server $Server -Credential $Credential } catch { $exists2=$null }
            if (-not $exists2) { return $cand2 }
            $suffix++
        }
    }
}

function Get-DefaultPasswordSecure {
    $dir = Get-ConfigDir; $file = Join-Path $dir 'defaultpwd.sec'
    if (Test-Path $file) { $encText=Get-Content -Path $file -ErrorAction Stop -Raw; return ConvertTo-SecureString -String $encText }
    Write-Host ''; Write-Host 'No default temp password found. Let us set one.' -ForegroundColor Cyan
    $chooseAuto = Read-Host 'Generate a strong random default temp password automatically? [Y/N] (default: Y)'
    $pwdPlain = $null
    if ([string]::IsNullOrWhiteSpace($chooseAuto) -or $chooseAuto.ToLowerInvariant() -in @('y','yes')) {
        $pwdPlain = New-TempPassword 16
        Write-Host 'Generated default temp password (displayed once for your records):' -ForegroundColor Yellow
        Write-Host $pwdPlain -ForegroundColor Yellow
    } else { $pwdPlain = Read-NonEmpty 'Enter default temp password' }
    $secureNew = ConvertTo-SecureString $pwdPlain -AsPlainText -Force
    $enc = ConvertFrom-SecureString -SecureString $secureNew
    Set-Content -Path $file -Value $enc -NoNewline
    Write-Host "Saved encrypted default temp password to $file" -ForegroundColor Green
    return $secureNew
}

function Get-TempPasswordForRun { param([string]$TempPassword,[switch]$UseAutoPassword)
    if ($PSBoundParameters.ContainsKey('TempPassword') -and -not [string]::IsNullOrWhiteSpace($TempPassword)) {
        $secure=ConvertTo-SecureString $TempPassword -AsPlainText -Force
        return [PSCustomObject]@{ Secure = $secure; Plain = $TempPassword }
    }
    if ($UseAutoPassword) {
        $plain=New-TempPassword 16; $secure=ConvertTo-SecureString $plain -AsPlainText -Force
        return [PSCustomObject]@{ Secure = $secure; Plain = $plain }
    }
    $secureDefault=Get-DefaultPasswordSecure
    return [PSCustomObject]@{ Secure = $secureDefault; Plain = $null }
}

function Find-ADGroupByName { param([string]$Name,[string]$Server,[pscredential]$Credential) try { Get-ADGroup -Filter "Name -eq '$Name'" -Server $Server -Credential $Credential } catch { $null } }

function Resolve-ManagerDN { param([string]$Server,[pscredential]$Credential)
    $mgrSam = Read-Host "Manager's samAccountName (leave blank to skip)"
    if ([string]::IsNullOrWhiteSpace($mgrSam)) { return $null }
    try {
        $mgr=Get-ADUser -Filter "SamAccountName -eq '$mgrSam'" -Server $Server -Credential $Credential -Properties DistinguishedName
        if ($mgr) { return $mgr.DistinguishedName }
        Write-Host "Manager not found by samAccountName '$mgrSam'." -ForegroundColor Yellow; return $null
    } catch { Write-Host "Error locating manager: $($_.Exception.Message)" -ForegroundColor Yellow; return $null }
}

function Export-OnboardingInfo { param([string]$ADUPN,[string]$CloudUPN,[string]$CloudAlias,[string]$OfficeType,[string]$DisplayName,[string]$SamAccountName)
    $dir  = Get-ConfigDir
    $file = Join-Path -Path $dir -ChildPath 'last_onboarding.json'
    $data = @{
        UserPrincipalName        = $ADUPN           # on-prem AD UPN
        CloudUserPrincipalName   = $CloudUPN        # first.last@sensapure.com
        CloudMailNickname        = $CloudAlias      # first.last alias
        OfficeType               = $OfficeType
        DisplayName              = $DisplayName
        SamAccountName           = $SamAccountName
    }
    $json = $data | ConvertTo-Json -Depth 3
    Set-Content -Path $file -Value $json -Encoding UTF8
    Log "Exported onboarding JSON for '$DisplayName' (ADUPN=$ADUPN, CloudUPN=$CloudUPN, OfficeType=$OfficeType)"
    Write-Host "Exported onboarding info to $file" -ForegroundColor Green
}

# ----------------- Execution -----------------

try { Ensure-ADModule } catch { Write-Error $_; exit 1 }
Log "Starting AD onboarding..."

$AdminCred = Get-ADAdminCredential -Target $Server
try { Get-ADDomain -Server $Server -Credential $AdminCred | Out-Null } catch {
    Write-Error "Could not connect to domain '$Server' with provided credentials: $($_.Exception.Message)"; Log "AD connect failed: $($_.Exception.Message)"; exit 1
}

Write-Host ''
Write-Host '--- New User Information ---' -ForegroundColor Green
$First     = Read-NonEmpty 'First name'
$Last      = Read-NonEmpty 'Last name'
$Title     = Read-NonEmpty 'Job title'
$Dept      = Read-NonEmpty 'Department'
$Company   = if ($ConfirmNames) { Read-NonEmpty 'Company' -Default 'Sensapure' } else { 'Sensapure' }
$StartDate = Read-Date 'Start date (e.g., 12/22/2025)'

$Description = "{0} - {1}" -f $Title, $StartDate.ToString('MM/dd/yy')

$defaultDisplay = "$First $Last"
$DisplayName = if ($ConfirmNames) { Read-NonEmpty 'Display name' -Default $defaultDisplay } else { $defaultDisplay }

$defaultSamBase   = Suggest-SamAccountNameBase -First $First -Last $Last
$defaultSamUnique = Ensure-UniqueSamProgressive -Server $Server -Credential $AdminCred -First $First -Last $Last
if ($ConfirmNames -and ($defaultSamUnique -ne $defaultSamBase)) { Write-Host "Note: '$defaultSamBase' is in use. Suggesting '$defaultSamUnique'." -ForegroundColor Yellow }
$Sam = if ($ConfirmNames) { Read-NonEmpty 'samAccountName' -Default $defaultSamUnique } else { $defaultSamUnique }

$OU  = Choose-OU -Server $Server -Credential $AdminCred -PreferredDN $DefaultOU
$ADUPN = "$Sam@$UPNSuffix"

# Cloud alias & UPN as first.last@sensapure.com
$firstAlias = ($First.ToLowerInvariant() -replace '[^a-z0-9]','')
$lastAlias  = ($Last.ToLowerInvariant()  -replace '[^a-z0-9]','')
$CloudAlias = "$firstAlias.$lastAlias"
$CloudUPN   = "$CloudAlias@$CloudDomain"

$pwdInfo   = Get-TempPasswordForRun -TempPassword $TempPassword -UseAutoPassword:$UseAutoPassword
$securePwd = $pwdInfo.Secure
$plainPwd  = $pwdInfo.Plain

$ManagerDN = Resolve-ManagerDN -Server $Server -Credential $AdminCred

# OfficeType prompt
$OfficeType = Read-Host "Office type (HQ or Warehouse)"
if ($OfficeType -notin @('HQ','Warehouse')) { Write-Warning "Invalid OfficeType. Defaulting to HQ."; $OfficeType='HQ' }

Write-Host ''
Write-Host 'Review:' -ForegroundColor Cyan
Write-Host " Name:           $DisplayName"
Write-Host " Given/Surname:  $First / $Last"
Write-Host " Title:          $Title"
Write-Host " Department:     $Dept"
Write-Host " Company:        $Company"
Write-Host " OfficeType:     $OfficeType"
Write-Host " Description:    $Description"
Write-Host " samAccountName: $Sam"
Write-Host " UPN:            $ADUPN"
Write-Host " OU:             $OU"
Write-Host " Server:         $Server"
Write-Host ' Enabled:        True'
Write-Host ' Change PW @Logon: True'
if ($plainPwd) { Write-Host " Temp Password:  $plainPwd" -ForegroundColor Yellow } else { Write-Host ' Temp Password:  (using encrypted default from config)' -ForegroundColor Yellow }
if ($ManagerDN) { Write-Host " Manager DN:     $ManagerDN" } else { Write-Host " Manager DN:     (none set)" }
Write-Host " Cloud UPN:      $CloudUPN"
Log "Review: $DisplayName | ADUPN=$ADUPN | CloudUPN=$CloudUPN | OfficeType=$OfficeType"

if ($DryRun) {
    Write-Warning 'DryRun mode — no changes will be made.'
    Export-OnboardingInfo -ADUPN $ADUPN -CloudUPN $CloudUPN -CloudAlias $CloudAlias -OfficeType $OfficeType -DisplayName $DisplayName -SamAccountName $Sam
    Log "AD DryRun complete."
    exit 0
}

$commonParams = @{ Server = $Server; Credential = $AdminCred }
$adParams = @{
    Name                  = $DisplayName
    GivenName             = $First
    Surname               = $Last
    DisplayName           = $DisplayName
    SamAccountName        = $Sam
    UserPrincipalName     = $ADUPN
    Title                 = $Title
    Department            = $Dept
    Company               = $Company
    Description           = $Description
    Path                  = $OU
    Enabled               = $true
    AccountPassword       = $securePwd
    ChangePasswordAtLogon = $true
}
if ($ManagerDN) { $adParams.Manager = $ManagerDN }

try {
    New-ADUser @commonParams @adParams
    Write-Host "User '$DisplayName' created successfully." -ForegroundColor Green
    Log "AD user created: $DisplayName ($Sam)"

    $grp = Find-ADGroupByName -Name 'SensapureUsers' -Server $Server -Credential $AdminCred
    if ($grp) {
        Add-ADGroupMember -Identity $grp -Members $Sam @commonParams
        Write-Host "Added '$Sam' to group 'SensapureUsers'." -ForegroundColor Green
        Log "AD group membership: SensapureUsers <- $Sam"
    } else {
        Write-Warning "Group 'SensapureUsers' not found."; Log "Group SensapureUsers not found."
    }

    Export-OnboardingInfo -ADUPN $ADUPN -CloudUPN $CloudUPN -CloudAlias $CloudAlias -OfficeType $OfficeType -DisplayName $DisplayName -SamAccountName $Sam

    if ($plainPwd) {
        Write-Host ''; Write-Host 'Provide this temporary password to the new hire:' -ForegroundColor Green
        Write-Host $plainPwd -ForegroundColor Cyan
        Log "Temp password generated and displayed (not logged)."
    } else {
        Write-Host ''; Write-Host 'Using the default temp password from the encrypted config file.' -ForegroundColor Green
        Log "Using encrypted default temp password."
    }
    Log "AD onboarding complete."
} catch {
    Write-Error "Failed to create user: $($_.Exception.Message)"
    Log ("AD error: " + $_.Exception.Message)
    throw
}
