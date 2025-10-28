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

# Create 'admin' user with no password
New-LocalUser -Name 'admin' -Description 'Admin account for Sensapure Devices' -NoPassword -PasswordNeverExpires
Add-LocalGroupMember -Group 'Administrators' -Member 'admin'

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force