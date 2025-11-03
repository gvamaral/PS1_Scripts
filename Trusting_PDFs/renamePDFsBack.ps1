$start = Get-Date

$folderPath = "S:\Raw Material Library"
$pdfFiles = Get-ChildItem -Path $folderPath -Recurse -Filter "*.pdf" -File
$badLogPath = "C:\Users\$env:USERNAME\Documents\pdf_unblock_log\rename_log_bad.txt"
$goodLogPath = "C:\Users\$env:USERNAME\Documents\pdf_unblock_log\rename_log_good.txt"
$suffix = "_UB"

# Create log directory if it doesn't exist
$logDir = Split-Path -Path $badLogPath
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$pdfFiles | 
Where-Object { $_.BaseName -like "*$suffix" } | 
ForEach-Object {
    $originalName = $_.BaseName -replace "$suffix$", ''
    $newName = "$originalName$($_.Extension)"
    try {
        Rename-Item -Path $_.FullName -NewName $newName
        Write-Host "Renamed '$($_.Name)' to '$newName'" -ForegroundColor Green
        # Log Write-Host above to a log file
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - File renamed $($_.Name) to $newName"
        # Append log entry to the log file
        Add-Content -Path $goodLogPath -Value $logEntry
    } 
    catch {
        # Log Write-Host above to a log file
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Failed to rename file: $($_.Name). Error: $($_.Exception.Message)"
        # Append log entry to the log file
        Add-Content -Path $badLogPath -Value $logEntry
        Write-Host "Failed to rename file: $($_.FullName). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Suffix '$suffix' has been removed from PDF files." -ForegroundColor Green

# Log time summary to both good and bad log files
$end = Get-Date
$duration = $end - $start
$minutes = [int]$duration.TotalMinutes
$seconds = $duration.Seconds
Write-Host ("took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds) -ForegroundColor DarkCyan
Add-Content -Path $badLogPath -Value ("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds)
Add-Content -Path $goodLogPath -Value ("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds)

# Clean up by removing the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force
exit