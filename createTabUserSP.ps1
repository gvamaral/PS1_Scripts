$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole($adminRole)) {
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

New-LocalUser -Name 'tabuser' -NoPassword -FullName 'Tablet User' -Description 'Account for Sensapure Tablets' -UserMayNotChangePassword
Add-LocalGroupMember -Group 'Users' -Member 'tabuser'

Remove-Item -Path $MyInvocation.MyCommand.Path -Force