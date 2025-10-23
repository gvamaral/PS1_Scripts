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

# Delete all other enabled local users except 'Administrator', 'itadmin', and 'tabuser'
$usersToKeep = @("Administrator", "itadmin", "tabuser")
$usersToDelete = Get-LocalUser | Where-Object { $_.Name -notin $usersToKeep -and $_.Enabled -eq $true }
foreach ($user in $usersToDelete) { 
    try { 
        Remove-LocalUser -Name $user.Name
    } 
    catch { 
        Write-Host "Failed to delete user: $($user.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Map network drive to S:
New-PSDrive -Name "S" -PSProvider "FileSystem" -Root "\\dc02.ad.sensapure.com\sensa" -Persist

$sourceFolder = "S:\IT\Toshiba FZ-G1"
$destinationFolder = "C:\Apps"

# Ensure the destination folder exists
if (!(Test-Path -Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder
}
# Copy applications from network share to local drive
Copy-Item -Path $sourceFolder\* -Destination $destinationFolder -Recurse -Force
Expand-Archive -Path "C:\Apps\Honeywell*.zip" -DestinationPath "C:\Apps" -Force
Expand-Archive -Path "C:\Apps\rover*.zip" -DestinationPath "C:\Apps\rover" -Force

# Set wallpaper
$wallpaperPath = "C:\Apps\SP_Wallpaper.jpg"
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\" -Name 'Wallpaper' -Value $wallpaperPath
RUNDLL32.EXE USER32.DLL,UpdatePerUserSystemParameters

# Install applications silently

# $logFile = "C:\Apps\install_log.log"
# $errFile = "C:\Apps\install_error.log"
# $installers = @(
#     "C:\Apps\Reader_en_install.exe",
#     "C:\Apps\Honeywell_2023.3_M-0.exe"
# )
# $msiInstallers = @(
#     "C:\Apps\rover\rover-installer.msi",
#     "C:\Apps\NinjaOne-Agent-InternalInfrastructure-MainOffice-Auto.msi"
# )
# foreach ($installer in $installers) { 
#     Start-Process -FilePath $installer -ArgumentList "/S" -Wait -RedirectStandardOutput $logFile -RedirectStandardError $errFile
# }
# foreach ($msiInstaller in $msiInstallers) {
#     $process = Start-Process msiexec.exe -ArgumentList "/i `"$msiInstaller`" /qn /norestart" -Wait -PassThru
#     if ($process.ExitCode -ne 0) {
#         Write-Host "Installation of $msiInstaller failed with exit code $($process.ExitCode)" -ForegroundColor Red
#     }
#     else {
#         Write-Host "Successfully installed $msiInstaller" -ForegroundColor Green
#     }
# }

# Rename computer based on last four digits of BIOS serial number
$SerialNumber = (Get-WmiObject Win32_BIOS).SerialNumber
$lastFour = $SerialNumber.Substring($SerialNumber.Length - 4)
$NewHostname = "SPTAB$lastFour"
Rename-Computer -NewName $NewHostname -Force -Restart

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force
