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

$roverPath = "C:\Apps\rover-installer.msi"
$roverZipPath = "C:\Apps\rover-installer-2.2.0.zip"

if (Test-Path $roverPath) {
    Write-Host "Installing Rover from $roverPath"
    Start-Process "msiexec.exe" -ArgumentList "/i `"$roverPath`"" -Wait
    Write-Host "Rover 2.2.0 installation completed."
} 
else {
    if (Test-Path $roverZipPath) {
        Write-Host "Extracting Rover installer from $roverZipPath"
        Expand-Archive -Path $roverZipPath -DestinationPath "C:\Apps\"
        if (Test-Path $roverPath) {
            Write-Host "Installing Rover from extracted MSI at $roverPath"
            Start-Process "msiexec.exe" -ArgumentList "/i `"$roverPath`"" -Wait
            Write-Host "Rover 2.2.0 installation completed."
        } 
        else {
            Write-Error "Rover installer not found after extraction at $roverPath."
        }
    } 
    else {
        Write-Host "Rover installer not found at $roverPath. Copying from S: Drive to C:\Apps."
        $sourcePath = "S:\IT\Software Install\M3\rover-installer-2.2.0.zip"
        $destinationPath = "C:\Apps\rover-installer-2.2.0.zip"

        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $destinationPath -Force
            Write-Host "Rover installer copied to $destinationPath. Extracting now."
            Expand-Archive -Path $destinationPath -DestinationPath "C:\Apps\"
            if (Test-Path $roverPath) {
                Write-Host "Installing Rover from extracted MSI at $roverPath"
                Start-Process "msiexec.exe" -ArgumentList "/i `"$roverPath`"" -Wait
                Write-Host "Rover 2.2.0 installation completed."
            } 
            else {
                Write-Error "Rover installer not found after extraction at $roverPath."
            }
        }
        else {
            Write-Error "Source installer not found at $sourcePath."
        }
    }
}