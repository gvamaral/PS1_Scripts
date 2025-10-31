$start = Get-Date

$folderPath = "S:\Raw Material Library"
$suffix = "_UB"
Get-ChildItem -Path $folderPath -Recurse -Filter "*.pdf" -File | Where-Object { $_.BaseName -like "*$suffix" } | ForEach-Object {
        $originalName = $_.BaseName -replace "$suffix$", ''
        $newName = "$originalName$($_.Extension)"
        try {
            Rename-Item -Path $_.FullName -NewName $newName
            Write-Host "Renamed '$($_.Name)' to '$newName'" -ForegroundColor Green
            # Log Write-Host above to a log file
            $logPath = "C:\Users\$env:USERNAME\Documents\pdf_unblock_log\rename_log_good.txt"
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - File renamed: $($file.Name) to $newName"
            # Create log directory if it doesn't exist
            $logDir = Split-Path -Path $logPath
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            # Append log entry to the log file
            Add-Content -Path $logPath -Value $logEntry -Apend
        } 
        catch {
            # Log Write-Host above to a log file
            $logPath = "C:\Users\$env:USERNAME\Documents\pdf_unblock_log\rename_log_bad.txt"
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Failed to rename file: $($file.Name). Error: $($file.Exception.Message)"
            # Create log directory if it doesn't exist
            $logDir = Split-Path -Path $logPath
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            # Append log entry to the log file
            Add-Content -Path $logPath -Value $logEntry -Apend
            Write-Host "Failed to rename file: $($_.FullName). Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
Write-Host "Suffix '$suffix' has been removed from PDF files." -ForegroundColor Green
$end = Get-Date
$duration = $end - $start
$minutes = [int]$duration.TotalMinutes
$seconds = $duration.Seconds
Write-Host "took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds -ForegroundColor DarkCyan

exit