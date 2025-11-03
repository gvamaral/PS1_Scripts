$start = Get-Date

$suffix = "_UB"
$folderPath = "S:\Raw Material Library"
$goodLogPath = "C:\Users\$env:USERNAME\Documents\pdf_unblock_log\unblock_log_good.txt"
$badLogPath = "C:\Users\$env:USERNAME\Documents\pdf_unblock_log\unblock_log_bad.txt"

# Create log directory if it doesn't exist
$logDir = Split-Path -Path $badLogPath
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Alert if folder path doesn't exist
if (-not (Test-Path -Path $folderPath)) {
    Write-Host "Folder $folderPath does not exist." -ForegroundColor Yellow
    exit
}

# Check if there are any PDF files in the folder
if (-not (Test-Path -Path $folderPath -Filter "*.pdf")) {
    Write-Host "No PDF files found in $folderPath" -ForegroundColor Yellow
    exit
}

$pdfFiles = Get-ChildItem -Path $folderPath -Recurse -Filter "*.pdf" -File
$existingTaggedFiles = $pdfFiles | Where-Object { $_.BaseName -like "*$suffix" }
$existingUntaggedFiles = $pdfFiles | Where-Object { $_.BaseName -notlike "*$suffix" }
$blockedFiles = $pdfFiles | Where-Object {
    try {
        Get-Content -Path "$($_.FullName):Zone.Identifier" -ErrorAction SilentlyContinue | Out-Null
        $true
    } catch {
        $false
    }
}

Write-Host "Total PDFs: $($pdfFiles.Count)" -ForegroundColor Cyan
Write-Host "Tagged PDFs: $($existingTaggedFiles.Count)" -ForegroundColor Cyan
Write-Host "Untagged PDFs: $($existingUntaggedFiles.Count)" -ForegroundColor Cyan
Write-Host "Blocked PDFs: $($blockedFiles.Count)" -ForegroundColor Cyan

# Unblock and renames all non tagged PDF files in the folder
if ($existingUntaggedFiles.Count -gt 0) {
    foreach ($file in $existingUntaggedFiles) {
        try {
            $newName = $file.BaseName + $suffix + $file.Extension
            Unblock-File -Path $file.FullName
            Rename-Item -Path $file.FullName -NewName $newName
            Write-Host "$($file.Name) was successfully unblocked and renamed" -ForegroundColor Green
          
            # Log Write-Host above to a log file
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unblocked and renamed: $($file.Name) to $newName"
            # Append log entry to the log file
            Add-Content -Path $goodLogPath -Value $logEntry
        } 
        catch {
            Write-Host "Failed to unblock file: $($file.Name). Error: $($file.Exception.Message)" -ForegroundColor Red
         
            # Log Write-Host above to a log file
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Failed to unblock file: $($file.Name). Error: $($file.Exception.Message)"
            # Append log entry to the log file
            Add-Content -Path $badLogPath -Value $logEntry
        }
    }
    Write-Host "All $($existingUntaggedFiles.Count) PDFs have been unblocked and renamed with suffix '$suffix'." -ForegroundColor Green
    
    $end = Get-Date
    $duration = $end - $start
    $minutes = [int]$duration.TotalMinutes
    $seconds = $duration.Seconds
    $pdfFiles = Get-ChildItem -Path $folderPath -Recurse -Filter "*.pdf" -File
    $existingTaggedFiles = $pdfFiles | Where-Object { $_.BaseName -like "*$suffix" }
    $existingUntaggedFiles = $pdfFiles | Where-Object { $_.BaseName -notlike "*$suffix" }
    $blockedFiles = $pdfFiles | Where-Object {
        try {
            Get-Content -Path "$($_.FullName):Zone.Identifier" -ErrorAction SilentlyContinue | Out-Null
            $true
        } catch {
            $false
        }
    }

    Write-Host "Total PDFs: $($pdfFiles.Count)" -ForegroundColor Cyan
    Write-Host "Tagged PDFs: $($existingTaggedFiles.Count)" -ForegroundColor Cyan
    Write-Host "Untagged PDFs: $($existingUntaggedFiles.Count)" -ForegroundColor Cyan
    Write-Host "Blocked PDFs: $($blockedFiles.Count)" -ForegroundColor Cyan

    Write-Host ("took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds) -ForegroundColor DarkCyan
    # Log Write-Host above to a log file
    $logEntry = ("took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds)
    # Append log entry to the log file
    Add-Content -Path $badLogPath -Value $logEntry
    Add-Content -Path $goodLogPath -Value $logEntry
    Read-Host -Prompt "Click Enter to exit :)  "
    
    # Clean up by removing the script itself
    Remove-Item -Path $MyInvocation.MyCommand.Path -Force
    exit
}
else {
    $end = Get-Date
    $duration = $end - $start
    $minutes = [int]$duration.TotalMinutes
    $seconds = $duration.Seconds
    Write-Host ("took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds) -ForegroundColor DarkCyan
    Write-Host "All PDF files already have the '$suffix' suffix." -ForegroundColor Green

    # Log Write-Host above to a log file
    $logEntry = ("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - took {0:D2}:{1:D2} m to process $($pdfFiles.Count) pdfs" -f $minutes, $seconds)
    $logEntry2 = "All PDF files already have the '$suffix' suffix."
    # Append log entry to the log file
    Add-Content -Path $badLogPath -Value $logEntry
    Add-Content -Path $badLogPath -Value $logEntry2
    Add-Content -Path $goodLogPath -Value $logEntry
    Add-Content -Path $goodLogPath -Value $logEntry2
    Read-Host -Prompt "Click Enter to exit :)  "
    
    # Clean up by removing the script itself
    Remove-Item -Path $MyInvocation.MyCommand.Path -Force
    exit
}
