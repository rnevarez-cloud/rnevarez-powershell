Function Write-Log {
 
  [CmdletBinding()]
   
  Param ([Parameter(Mandatory=$true)][string]$LogFile, [Parameter(Mandatory=$true)][string]$Message)
   
  Process{
    #Add Message to Log File with timestamp
    "$([datetime]::Now) : $Message" | Out-File -FilePath $LogFile -append;
   
    #Write the log message to the screen
    Write-host $([datetime]::Now) $Message
  }
}

Function Main {
  do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Snapshot Maintenance Script" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Server List:" -ForegroundColor Cyan
    foreach($s in $servers) {
      Write-Host $s -ForegroundColor Cyan
    }
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "1. Create snapshots" -ForegroundColor Yellow 
    Write-Host "2. List snapshots" -ForegroundColor Yellow
    Write-Host "3. Delete snapshots" -ForegroundColor Yellow
    Write-Host "0. Exit" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"
  
    $action = Read-Host "Enter choice"
  
  } until (($action -eq 1) -or ($action -eq 2) -or ($action -eq 3) -or ($action -eq 0)) 
  
  switch($action) {
    '1' {
      write-log $logfile "Creating snapshots"
      foreach($s in $servers) {
        Write-Host "Creating snapshot for $($s)" -ForegroundColor Green
        New-Snapshot -VM $s -name "Maintenance Window" -description "Created $(Get-Date -format yyyy-MM-dd) by $($Env:UserName)" -Memory:$true -RunAsync:$true | out-null
      }
      write-host "Snapshots created" -ForegroundColor Green
      write-log $logfile "Snapshots created"

      Main
    }
    '2' {
      write-log $logfile "Listing snapshots"
      foreach($s in $servers) {
        try {
          $snapshot = Get-Snapshot -VM $s -name "Maintenance Window" -ErrorAction Stop
        } catch {
          $snapshot = "Snapshot not found"
        }     
        
        Write-Host "$($s): $($snapshot)"

      }

      Main
    }
    '3' {
      write-log $logfile "Deleting snapshots"
      foreach($s in $servers) {      
        Write-Host "Deleting snapshot for $($s)" -ForegroundColor Red
        $snapshot = Get-Snapshot -VM $s -name "Maintenance Window"
        Remove-Snapshot -Snapshot $snapshot -Confirm:$false -RunAsync:$true | out-null
      }
      write-host "Snapshots deleted" -ForegroundColor Red
      write-log $logfile "Snapshots deleted"

      Main
    }
    '0' {
      exit
    }
  }
}

$LogFile = "C:\Downloads\Snapshot_Logs\$(Get-Date -format 'yyy-MM-dd-hh-mm')_snapshot_log.txt"

$VMWareCredential = get-credential -Message "Enter your vCenter credential" -UserName "domain\"
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
Connect-VIServer vcenter1 -Credential $VMWareCredential
connect-VIServer vcenter2 -Credential $VMWareCredential
Connect-VIServer vcenter3 -Credential $VMWareCredential

# if there's no connection to vCenter, exit
if (!($global:DefaultVIServers)) {
    write-host "You are not connected to vCenter...quitting" -ForegroundColor Red
    exit
    }

$tag = Get-Tag -Name "CONTOSO"
$servers = Get-VM -Tag $Tag

clear

Main
