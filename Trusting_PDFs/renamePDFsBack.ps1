$folderPath = "S:\Raw Material Library"
$suffix = "_UB"
Get-ChildItem -Path $folderPath -Recurse -Filter "*.pdf" -File | Where-Object { $_.BaseName -like "*$suffix" } | ForEach-Object {
        $originalName = $_.BaseName -replace "$suffix$", ''
        $newName = "$originalName$($_.Extension)"
        try {
            Rename-Item -Path $_.FullName -NewName $newName
            Write-Host "Renamed '$($_.Name)' to '$newName'" -ForegroundColor Green
        } 
        catch {
            Write-Host "Failed to rename file: $($_.FullName). Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
Write-Host "Suffix '$suffix' has been removed from PDF files." -ForegroundColor Green
exit