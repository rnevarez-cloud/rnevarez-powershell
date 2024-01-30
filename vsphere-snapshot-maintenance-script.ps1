##### Ricardo Nevarez - Application Maintenance VMware Script #####
##### Revision: 202401262 #####

$global:servers = $null
$global:allServers = $null    
$global:dc1Servers = $null
$global:dc2Servers = $null

Function Connect-VSphere {

  if (!($global:DefaultVIServers)) {
      $global:VMWareCredential = get-credential -Message "Enter your vCenter credential" -UserName "application\"
  }

  Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
  Connect-VIServer dc1-vc.ibm.application.local -Credential $VMWareCredential
  Connect-VIServer dc2-vc.application.local -Credential $VMWareCredential
}

Function Get-ApplicationVMs {
  $tag = Get-Tag -Name "Application"
  $global:allServers = Get-VM -Tag $Tag
  $global:dc1Servers = $allServers | Where-Object {$_.VMHost.Name -match "dc1"}
  $global:dc2Servers = $allServers | Where-Object {$_.VMHost.Name -match "dc2"}
}

Function Select-Datacenter {
  do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Select a datacenter" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "1. dc1" -ForegroundColor Yellow 
    Write-Host "2. dc2" -ForegroundColor Yellow
    Write-Host "3. Both" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"
  
    $datacenter = Read-Host "Enter choice"

  } until (($datacenter -match "[1-3]"))
    switch($datacenter) {
      '1' {
        $global:servers = $dc1Servers
      }
      '2' {
        $global:servers = $dc2Servers
      }
      '3' {
        $global:servers = $allServers
      }
    }
}
Function Main {
  do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Application Maintenance Script" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Server List:" -ForegroundColor Cyan
    foreach($s in $allServers) {
      Write-Host $s -ForegroundColor Cyan
    }
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Snapshot Options:" -ForegroundColor Cyan
    Write-Host "1. Create snapshots" -ForegroundColor Yellow 
    Write-Host "2. List snapshots" -ForegroundColor Yellow
    Write-Host "3. Delete snapshots" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "VMware Tool Options:" -ForegroundColor Cyan
    Write-Host "4. Upgrade VMware Tools" -ForegroundColor Yellow
    Write-Host "5. List VMware Tools" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "0. Exit" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------"
  
    $action = Read-Host "Enter choice"
  
  } until (($action -match "[0-5]")) 
  
  switch($action) {
    '1' {
      Select-Datacenter
      foreach($s in $servers) {
        Write-Host "Creating snapshot for $($s)" -ForegroundColor Yellow
        New-Snapshot -VM $s -name "Application Maintenance Window" -description "Created $(Get-Date -format yyyy-MM-dd) by $($Env:UserName)" -Memory:$true -RunAsync:$true -ErrorAction Stop
      }
      write-host "Snapshots created" -ForegroundColor Green

      Main
    }
    '2' {
      Select-Datacenter
      foreach($s in $servers) {
        try {
          $snapshot = Get-Snapshot -VM $s -name "Application Maintenance Window" -ErrorAction Stop
        } catch {
          $snapshot = "Snapshot not found"
        }     
        
        Write-Host "$($s): $($snapshot)"
      }

      Read-Host "Press Enter to continue"

      Main
    }
    '3' {
      Select-Datacenter
      foreach($s in $servers) {      
        Write-Host "Deleting snapshot for $($s)" -ForegroundColor Red
        $snapshot = Get-Snapshot -VM $s -name "Application Maintenance Window"
        Remove-Snapshot -Snapshot $snapshot -Confirm:$false -RunAsync:$true
      }
      write-host "Snapshots deleted" -ForegroundColor Green

      Main
    }
    '4' {
      Get-ApplicationVMs
      Select-Datacenter
      foreach($s in $servers) {      
        Write-Host "Upgrading VMware Tools for $($s)" -ForegroundColor Yellow
        Get-VMGuest $s | Update-Tools -RunAsync:$true
      }
      write-host "VMware Tools upgraded" -ForegroundColor Green

      Main
    }
    '5' {
      Get-ApplicationVMs
      Select-Datacenter
      Write-Host "Listing VMware Tools" -ForegroundColor Yellow
      $VMsArray= @()
      foreach($s in $servers) {   
        $obj = New-Object PSObject -Property @{
          VMName = $s
          VMwareHost = $s.VMHost.Name
          VMwareToolsStatus = $s.ExtensionData.Guest.ToolsStatus
          VMwareUpgradeStatus = $s.ExtensionData.Guest.ToolsVersionStatus2
          VMwareToolVersion = $s.ExtensionData.Guest.ToolsVersion
        }   

        $VMsArray += $obj
      }

      $VMsArray | Format-Table VMName,VMwareHost,VMwareToolsStatus,VMwareUpgradeStatus,VMwareToolVersion
      Read-Host "Press Enter to continue"

      Main
    }
    '0' {
      exit
    }
  }
}

Start-Transcript -Path "C:\ApplicationPSScripts\Application_Snapshot_Logs\$(Get-Date -format 'yyy-MM-dd-hh-mm')_snapshot_log.txt"

Connect-VSphere
Get-ApplicationVMs

clear

Main
