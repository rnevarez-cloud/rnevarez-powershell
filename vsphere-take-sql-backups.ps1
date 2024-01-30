Function Connect-VSphere {

    if (!($global:DefaultVIServers)) {
        $global:VMWareCredential = get-credential -Message "Enter your vCenter credential" -UserName "application\"
    exit
    }

    $global:applicationCred = Get-Credential -Message "Enter your application credential" -Username "application\"
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    Connect-VIServer dc1.application.local -Credential $VMWareCredential
    Connect-VIServer dc2.application.local -Credential $VMWareCredential
}

Function Pause {
    Write-Host "****************************************" -ForegroundColor Red
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Write-Host "****************************************" -ForegroundColor Red

    do {
        Write-Host "--------------------------------------------------------------------------"
        Write-Host "Do you want to continue or exit?" -ForegroundColor Cyan
        Write-Host "1. Continue" -ForegroundColor Yellow 
        Write-Host "2. Exit" -ForegroundColor Yellow
        $action = Read-Host "Enter choice"
    
    } until (($action -match "[1-2]")) 
    
    switch($action) {
        '1' {
            continue;
        }
        '2' {
            exit;
        }
    }
}

$global:backupDrive = @'
    (Get-Volume -FileSystemLabel *Backup*).DriveLetter
'@

$global:testPath = @"
                if(Test-Path $prodTempDirectory) {
                    Write-Host "Temp directory found" -ForegroundColor Green
                    Remove-Item "$($prodTempDirectory)\*" -Recurse -Force
                } else {
                    New-Item $prodTempDirectory -ItemType "Directory"
                }    
"@

$global:selectQuery = @"
    Invoke-Sqlcmd -Query "SELECT [name] FROM master.dbo.sysdatabases where ([name] like '%_application%'" -ErrorAction Stop
"@

$global:failedServers = New-Object System.Collections.ArrayList

$date = get-date -format yyyy-MM-dd
Connect-VSphere
clear

# if there's no connection to vCenter, exit
if (!($global:DefaultVIServers)) {
    write-host "You are not connected to vCenter...quitting" -ForegroundColor Red
    exit
    }

$Tag = "application"
Write-Host "Searching for VMs..." -ForegroundColor Yellow
$applicationSQLVMs = Get-VM -Tag $Tag | where-object {($_.guest.hostname -like "*DB*") -or ($_.guest.hostname -like "*SQL*") -and ($_.PowerState -eq "PoweredOn") -and ($_.guest.hostname -notlike "*TEST*")}
# sort by VM name
$applicationSQLVMs = $applicationSQLVMs | sort-object name
$SQLVMCount = $applicationSQLVMs.Count

do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "$($SQLVMCount) application SQL servers found:" -ForegroundColor Yellow
    foreach($VM in $applicationSQLVMs) {
        Write-Host $VM
    }
    Write-Host "--------------------------------------------------------------------------"

    $confirm = Read-Host "Continue? (Y\N)" 

} until (($confirm -eq 'Y') -or ($confirm -eq 'N'))

switch($confirm) {
    'Y' {
        foreach($VM in $applicationSQLVMs) {

            try {
                $prodBackupDrive = $VM | Invoke-VMScript -ScriptText $backupDrive -GuestCredential $applicationCred -ErrorAction Stop -WarningAction SilentlyContinue | Select -ExpandProperty ScriptOutput 
                $global:prodTempDirectory = "$($prodBackupDrive.trim()):\Temp"
            } catch {
                if ($_.Exception -match "failed to authenticate") {
                    Write-Host "Could not connect to $($VM). Skipping." -ForegroundColor Red
                    $global:failedServers.Add($VM) | out-null
                    continue; 
                } else {
                    Pause
                }
            }

            try {
                $VM | Invoke-VMScript -ScriptText $testPath -GuestCredential $applicationCred -ErrorAction Stop -WarningAction SilentlyContinue | Select -ExpandProperty ScriptOutput 
            } catch {
                Pause
            }
            
            try {
                $global:results = $VM | Invoke-VMScript -ScriptText $selectQuery -GuestCredential $applicationCred -ErrorAction Stop -WarningAction SilentlyContinue | Select -ExpandProperty ScriptOutput 
                $global:results = $results.Split([Environment]::NewLine).trim()
            } catch {
                Pause
            }

            Write-Host "---------------------------------------------------------"
            Write-Host "Starting SQL backups on $($VM)" -ForegroundColor Yellow
            Write-Host "$($VM) backup directory: $($prodTempDirectory)" 
            Write-Host "---------------------------------------------------------"

            $global:databases = New-Object System.Collections.ArrayList

            foreach ($r in $results) {
                if(($r -like "*application") -or ($r -like "*test")) {
                    $global:databases.Add($r) | out-null
                }
            }

            foreach ($d in $databases) {
                $global:fileName =  "$($d)-$date.bak"
                $global:backupPath = "$($prodTempDirectory)\$($fileName)"
                Write-Host "Backing up $($d)"

                try {
                    $global:backupScript = "Backup-SqlDatabase -ServerInstance localhost -Database $($d.toString()) -BackupFile $backupPath -CompressionOption On -CopyOnly -ErrorAction Stop"
                    $VM | Invoke-VMScript -ScriptText $backupScript -GuestCredential $applicationCred -ErrorAction Stop -WarningAction SilentlyContinue
                } catch {
                    Pause
                }   
            }
        }

        if($failedServers -ne $null) {
            Write-Host "--------------------------------------------------------------------------"
            Write-Host "Failed to connect to $($failedServers.Count) application Database servers:" -ForegroundColor Red                
            foreach($f in $failedServers) {
                Write-Host $f
            }
            Write-Host "Please connect to these servers manually and initiate database backups." -ForegroundColor Yellow
        }

    }
    'N' {
        exit
    }
}
