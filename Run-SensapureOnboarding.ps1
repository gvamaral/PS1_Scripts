
<#
.SYNOPSIS
Runs AD onboarding first, then M365 onboarding, with clear separation and logging.

.PARAMETER DryRun
Preview end-to-end. Both child scripts run in -DryRun mode.

.PARAMETER UsageLocation
UsageLocation for licensing. Default US.

.PARAMETER TempPassword
Override temp password for cloud user creation.

.PARAMETER UseAutoPassword
Generate random temp password for cloud user creation.

.PARAMETER NoCreateCloud
Do NOT auto-create cloud user if missing.

.PARAMETER Verbose
Show detailed messages from both scripts.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$UsageLocation = 'US',
    [string]$TempPassword,
    [switch]$UseAutoPassword,
    [switch]$NoCreateCloud
)

function Get-BaseDir {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) { return (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) }
    return (Get-Location).Path
}

$base = Get-BaseDir
$configDir = Join-Path $base 'config'
if (-not (Test-Path $configDir)) { New-Item -Path $configDir -ItemType Directory | Out-Null }
$logFile = Join-Path $configDir 'onboarding.log'

function Log { param([string]$Message) $stamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Add-Content -Path $logFile -Value "[$stamp] $Message" }

try {
    Log "Starting AD step..."
    $adScript = Join-Path $base 'Add-SensapureAdUser.ps1'
    if (-not (Test-Path $adScript)) { throw "AD script not found: $adScript" }

    # Build clean splat for AD script
    $adParams = @{}
    if ($DryRun) { $adParams['DryRun'] = $true }
    if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')) { $adParams['Verbose'] = $true }

    # Call AD script interactively so Get-Credential works
    & $adScript @adParams
    Log ("AD step completed." + ($(if ($DryRun) { " (DryRun)" } else { "" })))

    # JSON path
    $jsonFile = Join-Path $configDir 'last_onboarding.json'
    if (-not (Test-Path $jsonFile)) { throw "Onboarding JSON not found: $jsonFile" }

    Log "Starting M365 step..."
    $m365Script = Join-Path $base 'Add-SensapureM365.ps1'
    if (-not (Test-Path $m365Script)) { throw "M365 script not found: $m365Script" }

    # Build clean splat for M365 script
    $m365Params = @{
        ConfigFile    = $jsonFile
        UsageLocation = $UsageLocation
    }
    if ($DryRun) { $m365Params['DryRun'] = $true }
    if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')) { $m365Params['Verbose'] = $true }
    if ($TempPassword) { $m365Params['TempPassword'] = $TempPassword }
    if ($UseAutoPassword) { $m365Params['UseAutoPassword'] = $true }
    if ($NoCreateCloud) { $m365Params['NoCreateCloud'] = $true }

    & $m365Script @m365Params
    Log ("M365 step completed." + ($(if ($DryRun) { " (DryRun)" } else { "" })))

    Write-Host "Onboarding completed successfully." -ForegroundColor Green
    Log "Onboarding completed successfully."
} catch {
    Write-Error $_.Exception.Message
    Log ("Error: " + $_.Exception.Message)
    throw
}
