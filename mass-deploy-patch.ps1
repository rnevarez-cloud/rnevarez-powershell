### Install Application Patch ###
### Author: Ricardo Nevarez ###
### Revision: 20240126 ###

Clear-Host

$patch = Read-Host "Enter the path of the Application patch" ## Example: "C:\ApplicationDownloads\Application_Patch\Application_Patch"
$patch = "$($patch)\*"
$folders = Get-ChildItem D:\Application\ -Directory
Write-Host "--------------------------------------------------------------------------"
Write-Host $folders

do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Include or exclude?"
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "1. Include" -ForegroundColor Yellow 
    Write-Host "2. Exclude" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"

    $choice = Read-Host "Enter choice"

} until (($choice -match '[1-2]'))

switch($choice) {
    '1' {
        Write-Host "--------------------------------------------------------------------------"
        $include = Read-Host "Enter the clients that must be included (ex. ABC_Application,XYZ_Application)" ## List of folders to include. Example: "ABC_Application,XYZ_Application,DEF_Application"
        $include = $include.split(",")   
        $folders = Get-ChildItem D:\Application\ -Exclude $exclude -Directory
    }
    '2' {
        Write-Host "--------------------------------------------------------------------------"
        $exclude = Read-Host "Enter the clients that must be excluded (ex. ABC_Application,XYZ_Application)" ## List of folders to exclude. Example: "ABC_Application,XYZ_Application,DEF_Application"
        $exclude = $exclude.split(",")
        $folders = Get-ChildItem D:\Application\ -Exclude $exclude -Directory
    }
}

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
