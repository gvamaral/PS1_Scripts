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
