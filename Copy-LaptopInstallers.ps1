# Copy-LaptopInstallers.ps1
# Mirrors \\dc02\sensa\IT\Software Install\Laptops -> C:\Apps, extracts the
# Honeywell zip directly into C:\Apps, then installs the standard laptop-setup
# stack. Skips anything already installed (so reruns on the same machine are
# safe - uninstall the one app you want to retest and rerun). Logs every step
# to C:\Apps\install-log.txt. Self-deletes and closes the session at the end.
# By Gabriel Amaral.

$ErrorActionPreference = 'Continue'

$source  = '\\dc02\sensa\IT\Software Install\Laptops'
$dest    = 'C:\Apps'
$logPath = Join-Path $dest 'install-log.txt'

# --- Stage 1: make sure C:\Apps exists -----------------------------------
if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
}

# --- Logging helper ------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=================================================================="
Write-Log "Copy-LaptopInstallers.ps1 starting on $env:COMPUTERNAME as $env:USERNAME"

# --- Installed-app detection ---------------------------------------------
# Walks both the 64-bit and 32-bit Uninstall registry hives. Returns $true if
# any DisplayName matches any of the supplied wildcard patterns.
function Test-AppInstalled {
    param([string[]]$NamePatterns)
    $hives = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = Get-ItemProperty -Path $hives -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName }
    foreach ($pat in $NamePatterns) {
        $hit = $apps | Where-Object { $_.DisplayName -like $pat } | Select-Object -First 1
        if ($hit) {
            Write-Log "Detected installed: '$($hit.DisplayName)' (matched '$pat')"
            return $true
        }
    }
    return $false
}

# --- Stage 2: mirror the share to C:\Apps --------------------------------
Write-Log "Copying from $source to $dest (robocopy)"
robocopy $source $dest /E /R:2 /W:5 | Out-Null
$rc = $LASTEXITCODE
Write-Log "Robocopy finished with exit code $rc (0-7 = success, 8+ = error)"
if ($rc -ge 8) {
    Write-Log "Aborting: robocopy reported a failure. Nothing was installed." 'ERROR'
    return
}

# --- Stage 3: extract Honeywell zip directly into C:\Apps ----------------
# Zip already contains Honeywell_2023.3_M-0.exe at its root, so expanding
# straight to $dest drops the EXE into C:\Apps without an extra folder.
$honeyZip = Join-Path $dest 'Honeywell_2023.3_M-0.zip'
$honeyExe = Join-Path $dest 'Honeywell_2023.3_M-0.exe'
if ((Test-Path $honeyZip) -and -not (Test-Path $honeyExe)) {
    try {
        Write-Log "Extracting $honeyZip into $dest"
        Expand-Archive -Path $honeyZip -DestinationPath $dest -Force
        Write-Log "Honeywell zip extracted."
    } catch {
        Write-Log "Failed to extract Honeywell zip: $_" 'ERROR'
    }
} elseif (Test-Path $honeyExe) {
    Write-Log "Honeywell EXE already present, skipping extract."
} else {
    Write-Log "Honeywell zip not found at $honeyZip, skipping extract." 'WARN'
}

# --- Helper: launch an installer if it's present and not already installed
function Invoke-Installer {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string[]]$DetectNames = @(),
        [switch]$NoWait
    )
    if ($DetectNames.Count -gt 0 -and (Test-AppInstalled $DetectNames)) {
        Write-Log "$Name already installed - skipping."
        return
    }
    if (-not (Test-Path $FilePath)) {
        Write-Log "$Name not found at $FilePath - skipping." 'WARN'
        return
    }
    Write-Log "Starting install: $Name  (args: $($Arguments -join ' '))"
    try {
        $spParams = @{ FilePath = $FilePath; PassThru = $true }
        if ($Arguments.Count -gt 0) { $spParams.ArgumentList = $Arguments }
        if (-not $NoWait)           { $spParams.Wait = $true }

        $proc = Start-Process @spParams
        if ($NoWait) {
            Write-Log "$Name launched in background (PID $($proc.Id)). Script continues without waiting."
        } else {
            Write-Log "$Name finished with exit code $($proc.ExitCode)."
        }
    } catch {
        Write-Log "$Name failed to launch: $_" 'ERROR'
    }
}

# --- Stage 4: installs ---------------------------------------------------

# Google Chrome
Invoke-Installer -Name 'Google Chrome' `
    -FilePath (Join-Path $dest 'ChromeSetup.exe') `
    -Arguments @('/silent','/install') `
    -DetectNames @('Google Chrome')

# NinjaOne Agent (SensapureHQ MainOffice Auto)
$ninja = Join-Path $dest 'NinjaOne-Agent-SensapureHQ-MainOffice-Auto.msi'
if (Test-AppInstalled @('NinjaRMMAgent','NinjaOne Agent','*Ninja*Agent*')) {
    Write-Log "NinjaOne Agent already installed - skipping."
} elseif (-not (Test-Path $ninja)) {
    Write-Log "NinjaOne MSI not found at $ninja - skipping." 'WARN'
} else {
    Write-Log "Starting install: NinjaOne Agent (SensapureHQ MainOffice)"
    try {
        $proc = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList '/i', "`"$ninja`"", '/qn', '/norestart' `
            -Wait -PassThru
        Write-Log "NinjaOne Agent finished with exit code $($proc.ExitCode)."
    } catch {
        Write-Log "NinjaOne Agent failed to launch: $_" 'ERROR'
    }
}

# Canon GPlus UFRII print driver
Invoke-Installer -Name 'Canon GPlus UFRII Driver' `
    -FilePath (Join-Path $dest 'GPlus_UFRII_Driver_V260_W64_00.exe') `
    -Arguments @('/silent') `
    -DetectNames @('*Canon Generic Plus UFR*','*Canon*UFRII*')

# Honeywell 2023.3 M-0
# /S works for most InstallShield/NSIS wrappers. If it still shows a UI, try
# replacing with '/s /v"/qn"' for InstallShield MSI wrappers.
Invoke-Installer -Name 'Honeywell 2023.3 M-0' `
    -FilePath $honeyExe `
    -Arguments @('/S') `
    -DetectNames @('Honeywell*')

# Adobe Acrobat Reader
# IMPORTANT: Reader_en_install.exe on the share (~1.6 MB) is the *online
# bootstrap stub*, which does NOT honor /sAll /rs /msi silent flags - it always
# shows UI. To get a truly silent install, replace it on the share with the
# offline enterprise installer (~280 MB, named like AcroRdrDCx64_xxxx_en_US.exe)
# from Adobe's Enterprise FTP, then those flags will work.
# For now we launch it -NoWait so the script does not hang on the UI - finish
# the Adobe dialog by hand whenever you get to it, the rest of the installs
# keep moving.
Invoke-Installer -Name 'Adobe Acrobat Reader (manual dialog, runs in background)' `
    -FilePath (Join-Path $dest 'Reader_en_install.exe') `
    -Arguments @('/sAll','/rs','/msi','EULA_ACCEPT=YES') `
    -DetectNames @('Adobe Acrobat*','Adobe Reader*') `
    -NoWait

# Microsoft Office (Click-to-Run bootstrapper - runs in background)
Invoke-Installer -Name 'Microsoft Office (background install)' `
    -FilePath (Join-Path $dest 'OfficeSetup.exe') `
    -DetectNames @('Microsoft 365*','Microsoft Office*') `
    -NoWait

Write-Log "All requested installs kicked off. Office and Adobe may still be running."
Write-Log "Anything not auto-installed is sitting in C:\Apps for manual run."
Write-Log "Run complete. Log saved to $logPath"
Write-Log "=================================================================="

# --- Stage 5: self-delete + close ----------------------------------------
$self = $MyInvocation.MyCommand.Path
if ($self -and (Test-Path $self)) {
    Remove-Item -Path $self -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
exit
