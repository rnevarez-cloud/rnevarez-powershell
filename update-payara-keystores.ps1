##### Ricardo Nevarez - Update APP1/APP2 Certificates Script #####
##### Revision: 20240827 #####

Function Get-InternalWildCard {
    $ServerName = $ENV:COMPUTERNAME
    $CertType = "internal"
    #copy the right certificate to the server
    $SourcePath = [IO.Path]::Combine("\", $CertType)
    
    $global:DestPath = [IO.Path]::Combine("\")
    
    if (!(test-path $DestPath)) {
        Write-Host "--------------------------------------------------------------------------"
        write-host "Creating  directory" -ForegroundColor Green
        Write-Host "--------------------------------------------------------------------------"

        New-Item -ItemType Directory -force -Path $DestPath | out-null
        }
    else {
            # the cloudflare folder already exists so remove all the files from it
            Write-Host "--------------------------------------------------------------------------"
            write-host "Removing existing files from Cloudflare folder"
            Write-Host "--------------------------------------------------------------------------"
            Remove-Item $DestPath\* -Force
        }
    if (!(test-path $SourcePath)) { 
        
        $cred = Get-Credential INTERNAL\Username -Message "Enter your INTERNAL Credentials"
        
        try {
            New-PSDrive -name Z -PSProvider filesystem -root $SourcePath -Credential $cred -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "Could not connect to $($SourcePath). Please copy the certificate to the server manually and re-run the script." -ForegroundColor Red
            Exit;
        }

        $Certfiles = copy-item -PassThru -path Z:\*.* -Destination $DestPath 
                        
        Remove-PSDrive Z
    }
    else {
        # copy cert files
        $Certfiles = copy-item -PassThru -path $SourcePath\*.* -Destination $DestPath
                    
        }
    
    $global:CertPath = [System.IO.Path]::Combine($DestPath,($Certfiles | where-object {$_.name -like "*pfx*"}))
    $global:pfxpass = ConvertTo-SecureString -string (get-childitem -recurse -Path $DestPath | where-object {$_.name -like "*pwd*"} | get-content ) -AsPlainText -Force
    
}

function Remove-InternalWildCard {
    Write-Host "--------------------------------------------------------------------------"
    write-host "Removing  directory" -foregroundcolor Green
    remove-item $destpath\* -force
    Write-Host "--------------------------------------------------------------------------"
}

Function Get-Password {
    Param (
        $certpass
    )

    [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($certpass))
}

Clear-Host
if ($ENV:COMPUTERNAME -match "APP2") {
    $global:application = "APP2"
} elseif ($ENV:COMPUTERNAME -match "AP1|APP1") {
    $global:application = "APP1"
} else {
    Write-Host "Computer $($ENV:COMPUTERNAME) is not a APP1/APP2 server. This script can only be run on a APP1/APP2 server." -ForegroundColor Red
    exit
}

$digicert = 0
$tempDirectory = "C:\INTERNALScripts\temp"
$timestamp = get-date -format yyyy-MM-dd

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

$domainsDirLocation = Read-Host "Input the Internal Parent Directory"

$appInstall = "$($domainsDirLocation)\payara\domains"

$domains = Get-ChildItem $appInstall | Where-Object -Property Name -match "APP1|APP2"
$domainName = $domains | Select-Object -First 1 -ExpandProperty Name

$XMLfile = "$($appInstall)\$($domainName)\config\domain.xml"

Get-ChildItem "$($appInstall)\$($domainName)\config\" | Where-Object -Property Name -match "keystore.jks|cacerts.jks" | Copy-Item -Destination $tempDirectory

Write-Host "--------------------------------------------------------------------------"
Write-Host "Keystores copied to $($tempDirectory)" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"
Get-ChildItem $tempDirectory
Write-Host "--------------------------------------------------------------------------"

$keystore = "$($tempDirectory)\keystore.jks"
$cacerts = "$($tempDirectory)\cacerts.jks"

Get-ChildItem $tempDirectory | %{Copy-Item -Path "$($tempDirectory)\$($_.Name)" -Destination "$($tempDirectory)\$($_.Name)-backup-$timestamp"}

Write-Host "--------------------------------------------------------------------------"
Write-Host "Backups of the keystores have been made" -ForegroundColor Green
Get-ChildItem $tempDirectory | Where-Object -Property Name -match "backup"
Write-Host "--------------------------------------------------------------------------"

Write-Host "--------------------------------------------------------------------------"
Write-Host "Reading $($XMLfile) to get certificate alias" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

[xml]$domain = Get-Content $XMLfile

$alias = $domain.domain.configs.config.'network-config'.protocols.protocol.ssl | Where-Object -Property cert-nickname -notmatch "s1as|glassfish-instance|^$" | Select-Object -ExpandProperty cert-nickname | Get-Unique -AsString

Write-Host "--------------------------------------------------------------------------"
Write-Host "$($global:application) Certificate alias: $($alias)" -ForegroundColor Green
Write-Host "--------------------------------------------------------------------------"

do {
    Write-Host "--------------------------------------------------------------------------"
    Write-Host "Please select the certificate to use:" -ForegroundColor Yellow
    Write-Host "1. *.Internalcloud.com "
    Write-Host "2. Client Certificate"
    Write-Host "--------------------------------------------------------------------------"

    $action = Read-Host "Enter choice" 

} until (($action -match "[1-2]")) 
    
switch($action) {
    '1' {
        $digicert = 1
        Get-InternalWildCard
    }
    '2' {
        $global:CertPath = Read-Host "Enter the file path of the certificate"
        $global:pfxpass = Read-Host "Enter the certificate password" -AsSecureString
    }
}

Write-Host "--------------------------------------------------------------------------"
Write-Host "Getting certificate alias for $CertPath" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------"

$getAlias = (keytool -list -keystore $CertPath -storepass $(Get-Password $pfxpass) -v | Select-String -Pattern "Alias name: (.+)").Matches.Groups |Select-Object -Skip 1 -First 1 -ExpandProperty Value;

Write-Host "--------------------------------------------------------------------------"
write-host "Certificate alias: $($getAlias)" -ForegroundColor Green
Write-Host "--------------------------------------------------------------------------"

$masterPassword = Read-Host "Please enter the keystore master password" -AsSecureString

$importKeystore = "keytool -importkeystore -srckeystore $($CertPath) -srckeypass $(Get-Password $pfxpass) -destkeystore $($keystore) -srcstoretype PKCS12 -deststoretype JKS -srcstorepass $(Get-Password $pfxpass) -deststorepass $(Get-Password $masterPassword) -alias $($getAlias) -destalias $($alias) -destkeypass $(Get-Password $masterPassword) -noprompt"
$importCacerts = "keytool -importkeystore -srckeystore $($keystore) -destkeystore $($cacerts) -srcstoretype JKS -deststoretype JKS -srcstorepass $(Get-Password $masterPassword) -deststorepass $(Get-Password $masterPassword) -srcalias $($alias) -destalias $($alias) -noprompt"

Write-Host "--------------------------------------------------------------------------"
Write-Host "Importing $($CertPath) into $($keystore)" -ForegroundColor Cyan
Start-Process -FilePath "cmd.exe"  -ArgumentList "/c $($importKeystore)"
Write-Host "--------------------------------------------------------------------------"

Start-Sleep -Seconds 5

Write-Host "--------------------------------------------------------------------------"
Write-Host "Importing $($keystore) into $($cacerts)" -ForegroundColor Cyan
Start-Process -FilePath "cmd.exe"  -ArgumentList "/c $($importCacerts)"
Write-Host "--------------------------------------------------------------------------"

do {
    Write-Host "--------------------------------------------------------------------------"
    $copyToDomains = Read-Host "Copy keystores to $($global:application) domains? (Y/N)"

} until ($copyToDomains -match "Y|N")

switch($copyToDomains) {
    'Y' {
        foreach($d in $domains) {
            Write-Host "--------------------------------------------------------------------------"
            Write-Host "Copying $($keystore) to $($appInstall)\$($d)\config\" -ForegroundColor Cyan
            Copy-Item $keystore "$($appInstall)\$($d)\config\" -Force
            Write-Host "--------------------------------------------------------------------------"
            Write-Host "Copying $($cacerts) to $($appInstall)\$($d)\config\" -ForegroundColor Cyan
            Copy-Item $cacerts "$($appInstall)\$($d)\config\" -Force
            Write-Host "--------------------------------------------------------------------------"
        }

        Write-Host "--------------------------------------------------------------------------"
        Write-Host "Restarting $($global:application) domains" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------------------------"

        if ($global:application -eq "APP2") {
            $services = Get-Service -Name "APP2*"     
            $services | %{ restart-service $_ }    
        } else {
            $services = Get-Service -Name "APP1*" 
            $services | Where-Object -Property Name -NotMatch domain1 | %{ restart-service $_ }
            $services | Where-Object -Property Name -Match domain1 | %{ restart-service $_ }    
        }


        Write-Host "--------------------------------------------------------------------------"
        Write-Host "$($global:application) domains have been restarted!" -ForegroundColor Green
        Write-Host "--------------------------------------------------------------------------"

    }
    'N' {
        Write-Host "--------------------------------------------------------------------------"
        Write-Host "Please make sure to copy the updated files to the following domains:" -ForegroundColor Yellow
        foreach($d in $domains) {
            Write-Host $d
        }
        Write-Host "--------------------------------------------------------------------------"
    }
}

if($digicert -eq 1) {
    Remove-InternalWildCard
}
