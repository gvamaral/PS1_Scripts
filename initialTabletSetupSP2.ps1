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

# Map network drive to S:
$cred = Get-Credential -Credential "tempadmin"
New-PSDrive -Name "S" -PSProvider "FileSystem" -Root "\\dc02.ad.sensapure.com\sensa" -Credential $cred

$sourceFolder = "S:\IT\Toshiba FZ-G1"
$destinationFolder = "C:\Apps"

# Ensure the destination folder exists
if (!(Test-Path -Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder
}
# Copy applications from network share to local drive
Copy-Item -Path $sourceFolder\* -Destination $destinationFolder -Recurse -Force
Expand-Archive -Path "C:\Apps\Honeywell*.zip" -DestinationPath "C:\Apps" -Force
Expand-Archive -Path "C:\Apps\rover*.zip" -DestinationPath "C:\Apps" -Force

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force
