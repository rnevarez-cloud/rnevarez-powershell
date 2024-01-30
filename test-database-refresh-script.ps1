##### Ricardo Nevarez - Application Test Database Refresh Script #####
##### Revision: 20240129 #####

Clear-Host

##### Setting variables #####
$backupFile = 0
$tempDirectory = "E:\Temp"

Write-Host "This script will refresh a client's test database with production data." -ForegroundColor Cyan
$client = Read-Host "Enter client code"

do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Select the source of the database backup" -ForegroundColor Cyan
    Write-Host "1. Production SQL server" -ForegroundColor Yellow 
    Write-Host "2. SQL database backup file" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"

    $source = Read-Host "Enter choice"

} until (($source -eq 1) -or ($source -eq 2))

switch($source) {
    '1' {
        $productionServer = Read-Host "Enter the name of the client's PRODUCTION SQL server"
        
        $testConnection = Test-Connection $productionServer -Quiet -Count 1

        if(!($testConnection)) {
            Write-Host "--------------------------------------------------------------------------"
            Write-Host "Production SQL server is inaccessible from this server" -ForegroundColor Red
            Write-Host "--------------------------------------------------------------------------"

            $productionServer = Read-Host "Please copy a production SQL backup to this server and enter the file path (do not use quotes)"
        }
    }
    '2' {
        $productionServer = Read-Host "Enter the file path of the SQL database backup file (do not use quotes)"
    }
}

$testServer = [System.Net.Dns]::GetHostByName($env:computerName).HostName

do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Please verify the following information:" -ForegroundColor Cyan
    Write-Host "Client: $($client)" -ForegroundColor Yellow 
    Write-Host "Production Database Backup Location: $($productionServer)" -ForegroundColor Yellow
    Write-Host "Test Database Location: $($testServer)" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"

    $verify = Read-Host "Is the following information correct (Y/N)?"

} until (($verify -eq "Y") -or ($verify -eq "N"))

if($verify -eq "N") {
    exit
}

$timestamp = get-date -format yyyy-MM-dd

$productionDatabase = "$($client)_Application"
$testDatabase = "$($client)_test"
$tempDatabase = "$($testDatabase)_temp"

##### Grabbing version info for test before a restore from production #####
$testVersionInfo = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT VERSION, BUILD FROM SYSVAR"

if(Test-Path $productionServer) {
    $backupFile = 1
    $productionFilePath = $productionServer
} else {
    $prodBackupDrive = (Get-Volume -FileSystemLabel *Backup*).DriveLetter
    $prodBackupDriveUNC = "$($prodBackupDrive)$"
    $prodTempDirectory = "$($prodBackupDriveUNC)\Temp"
    $productionFilePath = "\\$($productionServer)\$($prodTempDirectory)\$($productionDatabase)_backup_$($timestamp).bak"
}

$testFilePath = "$($tempDirectory)\$($testDatabase)_backup_$($timestamp).bak"

##### Check for temp directory #####

if(Test-Path $tempDirectory) {
    do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Files in $($tempDirectory)" -ForegroundColor Cyan
    Get-ChildItem $tempDirectory
    Write-Host "--------------------------------------------------------------------------"

    $verify = Read-Host "Do you wish to clear the temp directory (Y/N)?"

    } until (($verify -eq "Y") -or ($verify -eq "N"))

    if($verify -eq "Y") {
        Write-Host "Clearing $($tempDirectory)" -ForegroundColor Yellow
        Remove-Item "$($tempDirectory)\*" -Recurse -Force
    } else {
        Write-Host "$($tempDirectory) will not be cleared" -ForegroundColor Yellow
    }
    
} else {
    New-Item $tempDirectory -ItemType "Directory"
}

if($backupFile -eq 0) {

    $prodTempUNCPath = "\\$($productionServer)\$($prodBackupDriveUNC)\Temp"

    if(Test-Path $prodTempUNCPath) {
        Remove-Item "$($prodTempUNCPath)\*" -Recurse -Force
    } else {
        New-Item $prodTempUNCPath -ItemType "Directory"
    }    

    ##### Taking SQL backups #####

    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Taking backup of $($productionDatabase) on $($productionServer)" -ForegroundColor Cyan
    Write-Host "File destination: $($productionFilePath)"
    Write-Host "--------------------------------------------------------------------------"

    try {
        Backup-SqlDatabase -ServerInstance $productionServer -Database $productionDatabase -BackupFile $productionFilePath -CompressionOption On -CopyOnly -ErrorAction Stop 
    } catch {
        Write-Host "****************************************" -ForegroundColor Red
        Write-Host "An error occurred:" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        Write-Host "****************************************" -ForegroundColor Red
        Read-Host "Please copy a SQL backup of the production database to the test server, then re-run the script." 

        exit;

    }

    Copy-Item -Path "\\$($productionServer)\$($prodBackupDriveUNC)\Temp\*" -Destination "$($tempDirectory)"
    $productionFilePath = "$($tempDirectory)\$($productionDatabase)_backup_$($timestamp).bak"

}

##### Taking SQL backups #####
Write-Host "--------------------------------------------------------------------------"
Write-Host "Taking backup of $($testDatabase) on $($testServer)" -ForegroundColor Cyan
Write-Host "File destination: $($testFilePath)"
Write-Host "--------------------------------------------------------------------------"

Backup-SqlDatabase -ServerInstance $testServer -Database $testDatabase -BackupFile $testFilePath -CompressionOption On -CopyOnly 

##### Restoring production data to test database #####
Write-Host "--------------------------------------------------------------------------"
Write-Host "Refreshing $($testDatabase) with $($productionDatabase) data." -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

Invoke-Sqlcmd -ServerInstance $testServer -QueryTimeout 0 -Query "ALTER DATABASE $($testDatabase) SET OFFLINE WITH ROLLBACK IMMEDIATE"

Write-Host "--------------------------------------------------------------------------"
Write-Host "Restoring $($productionFilePath) to $($testDatabase)" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

Restore-SqlDatabase -ServerInstance $testServer -Database $testDatabase -BackupFile $productionFilePath -ReplaceDatabase 

Write-Host "--------------------------------------------------------------------------"
Write-Host "Creating temporary database $($tempDatabase)" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

$RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("ApplicationWeb100db_Data", "$($tempDirectory)\$($testDatabase).mdf")
$RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("ApplicationWeb100db_Log", "$($tempDirectory)\$($testDatabase).ldf")

try {
    Restore-SqlDatabase -ServerInstance $testServer -Database $tempDatabase -BackupFile $testFilePath -RelocateFile @($RelocateData,$RelocateLog) -ErrorAction Stop
}
catch {
    Write-Host "****************************************" -ForegroundColor Red
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Read-Host "Temporary database could not be created. Please restore the test database manually." 
    Write-Host "****************************************" -ForegroundColor Red
}

Invoke-Sqlcmd -ServerInstance $testServer -QueryTimeout 0 -Query "ALTER DATABASE $($testDatabase) SET ONLINE"


##### Restoring test configuration values to test database #####

Write-Host "--------------------------------------------------------------------------"
Write-Host "Restoring test configuration values to test database" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

$table1 = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT table1 = STUFF((SELECT ',' + '[' + COLUMN_NAME + ']' FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'table1' FOR XML PATH('')), 1, 1, '')"
$table2 = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT table2 = STUFF((SELECT ',' + '[' + COLUMN_NAME + ']' FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'table2' FOR XML PATH('')), 1, 1, '')"
$table3 = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT table3 = STUFF((SELECT ',' + '[' + COLUMN_NAME + ']' FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'table3' FOR XML PATH('')), 1, 1, '')"
$table4 = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT table4 = STUFF((SELECT ',' + '[' + COLUMN_NAME + ']' FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'table4' FOR XML PATH('')), 1, 1, '')"
$table5 = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT table5 = STUFF((SELECT ',' + '[' + COLUMN_NAME + ']' FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'table5' FOR XML PATH('')), 1, 1, '')"
$table6 = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT table6 = STUFF((SELECT ',' + '[' + COLUMN_NAME + ']' FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'table6' FOR XML PATH('')), 1, 1, '')"

$query = @(
    "TRUNCATE TABLE table1; TRUNCATE TABLE table2; TRUNCATE TABLE table3; TRUNCATE TABLE table4"
    "SET IDENTITY_INSERT table1 ON; INSERT INTO table1 ($($table1.Item(0))) SELECT * FROM $($tempDatabase).dbo.table1; SET IDENTITY_INSERT table1 OFF"
    "SET IDENTITY_INSERT table2 ON; INSERT INTO table2 ($($table2.Item(0))) SELECT * FROM $($tempDatabase).dbo.table2; SET IDENTITY_INSERT table2 OFF"
    "SET IDENTITY_INSERT table3 ON; INSERT INTO table3 ($($table3.Item(0))) SELECT * FROM $($tempDatabase).dbo.table3; SET IDENTITY_INSERT table3 OFF"
    "SET IDENTITY_INSERT table4 ON; INSERT INTO table4 ($($table4.Item(0))) SELECT * FROM $($tempDatabase).dbo.table4; SET IDENTITY_INSERT table4 ON"
    "INSERT INTO table5 ($($table5.Item(0))) SELECT * FROM $($tempDatabase).dbo.table5"
    "INSERT INTO table6 ($($table6.Item(0))) SELECT * FROM $($tempDatabase).dbo.table6"
    "UPDATE API_CONF SET PORT = '21580' WHERE API_COD = 'XXX'"
    )   

foreach($q in $query) {
    try {
        Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query $q -ErrorAction Stop
    }
    catch {
        Write-Host "****************************************" -ForegroundColor Red
        Write-Host "An error occurred:" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        Read-Host "Please restore the table manually, then press 'Enter' to continue." 
        Write-Host "****************************************" -ForegroundColor Red
    }
}

##### Grabbing version info for test after a restore from production #####
$prodVersionInfo = Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "SELECT VERSION, BUILD FROM SYSVAR"

Invoke-Sqlcmd -ServerInstance $testServer -QueryTimeout 0 -Query "DROP DATABASE $($tempDatabase)" 

$detectAPP = Invoke-Sqlcmd -ServerInstance $testServer -QueryTimeout 0 -Query "SELECT NAME FROM master.sys.server_principals WHERE NAME = '$($client)_APPi'"

Write-Host "--------------------------------------------------------------------------"
Write-Host "Checking for APP..." -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

if($null -ne $detectAPP) {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "APP integration found! Preserving APP login." -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------"
    
    Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "EXEC sp_change_users_login  Auto_Fix, $($client)_APPi; GRANT CONTROL ON CERTIFICATE::SSN TO $($client)_APPi; GRANT CONTROL ON SYMMETRIC KEY::SSN_Key_01 TO $($client)_APPi"
} else {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "APP integration not found. Skipping." -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"
}

Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Application123RJM123Systems123'; ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY"

Write-Host "--------------------------------------------------------------------------"
Write-Host "$($testDatabase) refresh complete!" -ForegroundColor Green
Write-Host "--------------------------------------------------------------------------"

##### Comparing versions between production and test databases #####
if(($testVersionInfo.Version -ne $prodVersionInfo.Version) -and ($testVersionInfo.Build -ne $prodVersionInfo.Build)) {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Version mismatch detected between production and test. Please make sure to run scripts on the test environment." -ForegroundColor Yellow
    Write-Host "Test Version Information: $($testVersionInfo.Version) ($($testVersionInfo.Build))" -ForegroundColor Cyan
    Write-Host "Production Version Information: $($prodVersionInfo.Version) ($($prodVersionInfo.Build))" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------"
}

$testAppServer = Read-Host "Enter the name of the client's TEST Application WEB server"
$testInstanceNumber = Read-Host "Enter the client's TEST Application instance number"

$testConnection = Test-Connection $testAppServer -Quiet -Count 1

if(!($testConnection)) {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Application test server inaccessible from this server. Please clear the ColdFusion caches manually." -ForegroundColor Red
    Write-Host "--------------------------------------------------------------------------"
} else {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Restarting $($client)'s Application TEST instance" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------"

    Invoke-Command -ComputerName $testAppServer -ScriptBlock {
        $testApplicationInstance = Get-Service "ColdFusion **** Application Server Application_$($testInstanceNumber)"
        $testApplicationInstance | %{ Restart-Service $_ }
    }

    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Restart complete!" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------"
}
