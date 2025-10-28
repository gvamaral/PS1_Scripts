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

# Delete all other enabled local users except Administrator and admin
$usersToKeep = @("Administrator", "admin")
$usersToDelete = Get-LocalUser | Where-Object { $_.Name -notin $usersToKeep -and $_.Enabled -eq $true }
foreach ($user in $usersToDelete) { 
    try { 
        Remove-LocalUser -Name $user.Name
    } 
    catch { 
        Write-Host "Failed to delete user: $($user.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Delete Rover application
$roverPath = "C:\Program Files (x86)\Zumasys"
(Get-WmiObject Win32_Product -Filter "Name = 'Rover ERP'").Uninstall()
Remove-Item -Path $roverPath -Recurse -Force -ErrorAction SilentlyContinue

# Remove mapped network drives
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like "\\*" } | ForEach-Object { Remove-PSDrive -Name $_.Name -Force }

# Rename computer to default name
$SerialNumber = (Get-WmiObject Win32_BIOS).SerialNumber
Rename-Computer -NewName "TBR-$SerialNumber" -Force -Restart

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force