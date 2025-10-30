# Define the network share and zone
$networkShare = "\\dc02.ad.sensapure.com"
$zone = 1  # Local Intranet Zone

# Registry path for Internet Explorer zones
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains"

# Extract the domain or network share name
$domain = $networkShare -replace "\\", ""

# Create the registry key for the domain
if (-not (Test-Path "$regPath\$domain")) {
    # Remove the server from the Local Intranet zone
    Remove-Item -Path "$registryPath\$serverName" -Recurse -Force
    Write-Output "The network share '$networkShare' has been removed from the Local Intranet zone."
} else {
    Write-Output "The network share '$networkShare' was not found in the Local Intranet zone."
}
