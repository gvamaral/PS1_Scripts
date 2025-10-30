# Define the network share and zone
$networkShare = "\\dc02.ad.sensapure.com"
$zone = 1  # Local Intranet Zone

# Registry path for Internet Explorer zones
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains"

# Extract the domain or network share name
$domain = $networkShare -replace "\\", ""

# Create the registry key for the domain
if (-not (Test-Path "$regPath\$domain")) {
    New-Item -Path "$regPath\$domain" -Force | Out-Null
}

# Set the zone value
Set-ItemProperty -Path "$regPath\$domain" -Name "*" -Value $zone

Write-Host "Network share '$networkShare' has been added to the Local Intranet zone."

shutdown /r /t 30 /c "System will restart in 30 seconds to apply changes." /f

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force