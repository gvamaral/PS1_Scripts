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
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -Value $wallpaperPath
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -Value "2" # 2 = Stretch, 0 = Center, 6 = Fit, etc.
gpupdate /force

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force
