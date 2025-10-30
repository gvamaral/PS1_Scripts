# Define the network share and zone
$networkShare = "\\dc02.ad.sensapure.com"

# Registry path for Internet Explorer zones
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains"

# Extract the domain or network share name
$domain = $networkShare -replace "\\", ""

# Create the registry key for the domain
if (Test-Path "$regPath\$domain") {
    # Remove the server from the Local Intranet zone
    Remove-Item -Path "$regPath\$domain" -Recurse -Force
    Write-Output "The network share '$networkShare' has been removed from the Local Intranet zone."
} else {
    Write-Output "The network share '$networkShare' was not found in the Local Intranet zone."
}

shutdown /r /t 30 /c "System will restart in 30 seconds to apply changes." /f

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force