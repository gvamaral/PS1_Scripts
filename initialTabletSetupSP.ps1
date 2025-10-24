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

# Create 'itadmin' user
$Secure_String_Pwd = Read-Host -Prompt "Enter password for itadmin user" -AsSecureString
New-LocalUser -Name 'itadmin' -Description 'Admin account for Sensapure Devices' -Password $Secure_String_Pwd
Add-LocalGroupMember -Group 'Administrators' -Member 'itadmin'

# Create 'tabuser' user
New-LocalUser -Name 'tabuser' -Description 'Account for Sensapure Tablets' -NoPassword
Add-LocalGroupMember -Group 'Users' -Member 'tabuser'

# Configure auto-login for 'tabuser'
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LimitBlankPasswordUse" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value "1"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUsername" -Value "tabuser"
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -ErrorAction SilentlyContinue

# Rename computer based on last four digits of BIOS serial number
$SerialNumber = (Get-WmiObject Win32_BIOS).SerialNumber
$lastFour = $SerialNumber.Substring($SerialNumber.Length - 4)
$NewHostname = "SPTAB$lastFour"
Rename-Computer -NewName $NewHostname -Force -Restart

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force
