$server = '.'
$backupPath = 'C:\Temp\'

$databases = Invoke-Sqlcmd -ServerInstance $Server -Query "SELECT [name] FROM master.dbo.sysdatabases where [name] like '%_web%'"

foreach ($database in $databases)
{
    $timestamp = get-date -format yyyy-MM-dd
    $fileName =  "$($database.name)-$timestamp.bak"
    $filePath = Join-Path $backupPath $fileName

Backup-SqlDatabase -ServerInstance $server -Database $database.name -BackupFile $filePath -CompressionOption On -CopyOnly 
}
