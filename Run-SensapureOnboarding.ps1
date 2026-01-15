
<#
.SYNOPSIS
Runs AD onboarding first, then M365 onboarding, with clear separation and logging.

.PARAMETER DryRun
Run in preview mode. AD will export JSON; M365 step runs in DryRun as well.

.PARAMETER CreateCloudIfMissing
When set, creates cloud user if not found.

.PARAMETER UsageLocation
UsageLocation for licensing. Default US.

.PARAMETER Verbose
Show detailed messages from both scripts.
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

    if ($DryRun) {
        & $adScript -DryRun @PSBoundParameters
        Log "AD step completed (DryRun)."
    } else {
        & $adScript @PSBoundParameters
        Log "AD step completed."
    }

    $jsonFile = Join-Path $configDir 'last_onboarding.json'
    if (-not (Test-Path $jsonFile)) { throw "Onboarding JSON not found: $jsonFile" }

    Log "Starting M365 step..."
    $m365Script = Join-Path $base 'Add-SensapureM365.ps1'
    if (-not (Test-Path $m365Script)) { throw "M365 script not found: $m365Script" }

    if ($DryRun) {
        & $m365Script -ConfigFile $jsonFile -UsageLocation $UsageLocation -DryRun @PSBoundParameters
        Log "M365 step completed (DryRun)."
    } else {
        if ($CreateCloudIfMissing) {
            & $m365Script -ConfigFile $jsonFile -UsageLocation $UsageLocation -CreateCloudIfMissing @PSBoundParameters
        } else {
            & $m365Script -ConfigFile $jsonFile -UsageLocation $UsageLocation @PSBoundParameters
        }
        Log "M365 step completed."
    }

    Write-Host "Onboarding completed successfully." -ForegroundColor Green
    Log "Onboarding completed successfully."
} catch {
    Write-Error $_.Exception.Message
    Log ("Error: " + $_.Exception.Message)
    throw
}