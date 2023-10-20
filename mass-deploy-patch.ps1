### Mass Deploy Patch
### Author: Ricardo Nevarez

clear

$patch = Read-Host "Enter the path of the application patch" ## Example: "C:\Downloads\Patch"
$exclude = Read-Host "Enter the clients that must be excluded (ex. app_1,app_2,app_3)" ## List of folders to exclude. Example: "app_1,app_2,app_3"
$exclude = $exclude.split(",")

$folders = Get-ChildItem c:\webroot\ -Exclude $exclude -Directory

$patch = "$($patch)\*"

Write-Host $patch

do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "The patch will be applied to the following folders:"
    foreach($f in $folders) {
        Write-Host $f
    }
    Write-Host "--------------------------------------------------------------------------"

    $confirm = Read-Host "Continue? (Y\N)"

} until (($confirm -eq 'Y') -or ($confirm -eq 'N'))

switch($confirm) {
    'Y' {
        foreach ($folder in $folders)
            { 
            Write-Host "Copying $patch to $folder" -ForegroundColor Cyan
            Copy-Item $patch -Destination $folder -force -recurse
            }
    }
    'N' {
        exit
    }
}
