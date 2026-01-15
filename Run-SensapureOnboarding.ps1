
<#
.SYNOPSIS
Runs AD onboarding first, then M365 onboarding, with clear separation and logging.

.PARAMETER DryRun
Preview end-to-end. Both child scripts run in -DryRun mode.

.PARAMETER CreateCloudIfMissing
When set, M365 script will create cloud user if missing (default behavior anyway).

.PARAMETER UsageLocation
UsageLocation for licensing. Default US.

.PARAMETER Verbose
Show detailed messages from both scripts (common parameter).
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$CreateCloudIfMissing,
    [string]$UsageLocation = 'US'
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
    # Default behavior of M365 script is to create cloud user if missing,
    # so we do not have to pass a flag unless you add -NoCreateCloud in the future.

    & $m365Script @m365Params
    Log ("M365 step completed." + ($(if ($DryRun) { " (DryRun)" } else { "" })))

    Write-Host "Onboarding completed successfully." -ForegroundColor Green
    Log "Onboarding completed successfully."
} catch {
    Write-Error $_.Exception.Message
    Log ("Error: " + $_.Exception.Message)
    throw
}
