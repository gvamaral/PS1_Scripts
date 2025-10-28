# Ensure the script is running with administrative privileges
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole($adminRole)) {
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

# Run Windows Update and install all available updates
Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
Import-Module PSWindowsUpdate
# Get list of available updates
$updates = Get-WindowsUpdate
if ($updates) {
    # Install all available updates
    Install-WindowsUpdate -AcceptAll -AutoReboot
} else {
    Write-Host "No updates available." -ForegroundColor Green
}
# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force