$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole($adminRole)) {
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

$Secure_String_Pwd = Read-Host -Prompt "Enter password for itadmin user" -AsSecureString
New-LocalUser -Name 'itadmin' -Description 'Admin account for Sensapure Devices' -Password $Secure_String_Pwd  -PasswordNeverExpires
Add-LocalGroupMember -Group 'Administrators' -Member 'itadmin'

Remove-Item -Path $MyInvocation.MyCommand.Path -Force