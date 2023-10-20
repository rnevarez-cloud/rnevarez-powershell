###Test Database Refresh Script
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

$productionDatabase = "$($client)_production"
$testDatabase = "$($client)_test"
$tempDatabase = "$($testDatabase)_temp"

if(Test-Path $productionServer) {
    $backupFile = 1
    $productionFilePath = $productionServer
} else {
    $productionFilePath = "$($tempDirectory)\$($productionDatabase)_backup_$($timestamp).bak"
}

$testFilePath = "$($tempDirectory)\$($testDatabase)_backup_$($timestamp).bak"

##### Check for temp directory #####

if(Test-Path $tempDirectory) {
    Remove-Item "$($tempDirectory)\*" -Recurse -Force
} else {
    New-Item "tempDirectory" -ItemType "Directory"
}

if($backupFile -eq 0) {
    if(Test-Path "\\$($productionServer)\E$\Temp\") {
        Remove-Item "\\$($productionServer)\E$\Temp\*" -Recurse -Force
    } else {
        New-Item "\\$($productionServer)\E$\Temp" -ItemType "Directory"
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
        Read-Host "Please copy a SQL backup of the production database to the test server, then re-run the script." 
        Write-Host "****************************************" -ForegroundColor Red
    }
    Copy-Item -Path "\\$($productionServer)\E$\Temp\*" -Destination "$($tempDirectory)"

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

$RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("db_Data", "$($tempDirectory)\$($testDatabase).mdf")
$RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("db_Log", "$($tempDirectory)\$($testDatabase).ldf")

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

$query = @(
    "TRUNCATE TABLE IZ_CONFIG; TRUNCATE TABLE SECURITY_SSO; TRUNCATE TABLE NMSSO; TRUNCATE TABLE SAMLIDPS"
    "SET IDENTITY_INSERT IZ_CONFIG ON; INSERT INTO IZ_CONFIG ($($table1.Item(0))) SELECT * FROM $($tempDatabase).dbo.IZ_CONFIG; SET IDENTITY_INSERT IZ_CONFIG OFF"
    "SET IDENTITY_INSERT SECURITY_SSO ON; INSERT INTO SECURITY_SSO ($($SECURITY_SSO.Item(0))) SELECT * FROM $($tempDatabase).dbo.SECURITY_SSO; SET IDENTITY_INSERT SECURITY_SSO OFF"
    "SET IDENTITY_INSERT NMSSO ON; INSERT INTO NMSSO ($($NMSSO.Item(0))) SELECT * FROM $($tempDatabase).dbo.NMSSO; SET IDENTITY_INSERT NMSSO OFF"
    "SET IDENTITY_INSERT SAMLIDPS ON; INSERT INTO SAMLIDPS ($($SAMLIDPS.Item(0))) SELECT * FROM $($tempDatabase).dbo.SAMLIDPS; SET IDENTITY_INSERT SAMLIDPS ON"
    "SET IDENTITY_INSERT NELNET ON; INSERT INTO NELNET ($($NELNET.Item(0))) SELECT * FROM $($tempDatabase).dbo.NELNET; SET IDENTITY_INSERT NELNET OFF"
    "UPDATE API_CONF SET PORT = 'XXXXX' WHERE API_COD = 'INTEGRATION'"
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

Invoke-Sqlcmd -ServerInstance $testServer -Query "DROP DATABASE $($tempDatabase)"

$detectJRM = Invoke-Sqlcmd -ServerInstance $testServer -QueryTimeout 0 -Query "SELECT NAME FROM master.sys.server_principals WHERE NAME = '$($client)_integration'"

Write-Host "--------------------------------------------------------------------------"
Write-Host "Checking for Integration..." -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

if($null -ne $detectJRM) {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Integration found! Preserving Integration login." -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------"
    
    Invoke-Sqlcmd -ServerInstance $testServer -Database $testDatabase -Query "EXEC sp_change_users_login  Auto_Fix, $($client)_integration; GRANT CONTROL ON CERTIFICATE::SSN TO $($client)_integration; GRANT CONTROL ON SYMMETRIC KEY::KEY TO $($client)_integration"
} else {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Integration not found. Skipping." -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"
}

Write-Host "--------------------------------------------------------------------------"
Write-Host "$($testDatabase) refresh complete!" -ForegroundColor Green
Write-Host "--------------------------------------------------------------------------"

$testAppServer = Read-Host "Enter the name of the client's TEST CONTOSO WEB server"
$testInstanceNumber = Read-Host "Enter the client's TEST CONTOSO instance number"

$testConnection = Test-Connection $testAppServer -Quiet -Count 1

if(!($testConnection)) {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "CONTOSO test server inaccessible from this server. Please clear the caches manually." -ForegroundColor Red
    Write-Host "--------------------------------------------------------------------------"
} else {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Restarting $($client)'s CONTOSO TEST instance" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------"

    Invoke-Command -ComputerName $testAppServer -ScriptBlock {
        $testSonisInstance = Get-Service "Application Server contoso_$($testInstanceNumber)"
        $testSonisInstance | %{ Restart-Service $_ }
    }

    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Restart complete!" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------"
}
