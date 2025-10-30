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

# Unblock and renames all non tagged PDF files in the folder
if ($existingUntaggedFiles.Count -gt 0) {
    foreach ($file in $existingUntaggedFiles) {
        try {
            $newName = $file.BaseName + $suffix + $file.Extension
            Unblock-File -Path $file.FullName
            Rename-Item -Path $file.FullName -NewName $newName
            Write-Host "$($file.Name) was sucessfully unblocked and renamed" -ForegroundColor Green
        } 
        catch {
            Write-Host "Failed to unblock file: $($file.Name). Error: $($file.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "All $($existingUntaggedFiles.Count) PDFs have been unblocked and renamed with suffix '$suffix'." -ForegroundColor Green
    Read-Host -Prompt "Click Enter to exit :)  "
    exit
}
else {
    Write-Host "All PDF files already have the '$suffix' suffix." -ForegroundColor Green
    Read-Host -Prompt "Click Enter to exit :)  "
    exit
}
