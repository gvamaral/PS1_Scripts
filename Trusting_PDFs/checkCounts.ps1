$start = Get-Date

$suffix = "_UB"
$folderPath = "S:\Raw Material Library"

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

$end = Get-Date
$duration = $end - $start
$minutes = [int]$duration.TotalMinutes
$seconds = $duration.Seconds

Write-Host ("took {0:D2}:{1:D2} to process {3:D2} pdfs" -f $minutes, $seconds, $pdfFiles.Count) -ForegroundColor Violet

# Cleanup of the script itself
Remove-Item -Path $MyInvocation.MyCommand.Path -Force