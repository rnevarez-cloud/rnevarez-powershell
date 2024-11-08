function Get-RoyalAdComputers {
    param (
        [parameter(Mandatory=$true)]
        [string]$AdDomain,
        [string]$AdServer,
	    [string]$SearchBase,
        [string]$SearchScope = "Subtree",
        [string]$SearchFilter = "*",
        [string]$UseAdminConsole = "False",
		[switch]$IncludeAdTrusts,
        [parameter(Mandatory=$true)]
		[string]$RsgId
    )

    Clear-Host
    Import-Module ActiveDirectory -Force
    $totalResults = @{}
    [System.Collections.ArrayList]$array = @()
    [System.Collections.ArrayList]$pathArray = @()
    [System.Collections.ArrayList]$folderNames = @(
        "Internal",
        "Clients A,B,C",
        "Clients D,E,F",
        "Clients G,H,I",
        "Clients J,K,L",
        "Clients M,N,O",
        "Clients P,Q,R",
        "Clients S,T,U",
        "Clients V,W,X",
        "Clients Y,Z"
        )
    $customers = @{}
    $csvpath = "C:\Company\RoyalTS\Scripts\customers-2024-10-16.csv"
    Import-CSV $csvpath | ForEach-Object { $customers[$_.Code] = $_.Name }
    #Add alphabetical folders
    foreach($n in $foldernames) {
        $array.add((
        New-Object -TypeName System.Management.Automation.PSObject -Property @{
            "Type"			    = "Folder";
            "CredentialsFromParent" = "true";
            "Path"			    = "/";
            "Name"			    = "$($n)";
            "SecureGatewayFromParent" = "True";
            "RoyalServerFromParent" = "True";
            "ConnectTaskFromParent" = "True";
            "DisconnectTaskFromParent" = "True";
        }
    )) | Out-Null
    }
    
    $AdDomains = @($AdDomain)
	
    if ($includeAdTrusts) {
		$AdDomains += Get-ADTrust -Filter * | Sort-Object -Property Name | Select-Object -ExpandProperty Name
	}

	$computers = @()
	foreach($adDomain in $ADDomains){
        
        $AdServer = $null
    
            $status = @{ "ServerName" = $AdDomain; "TimeStamp" = (Get-Date -f s)}
            $result = Test-Connection $AdDomain -Count 1 -ErrorAction SilentlyContinue
			
            if ($result)    { 
                $StatusResult =  "Up"
                $statusIP =  ($result.IPV4Address).IPAddressToString
                $AdServer = $statusIP
            } 

        if ($AdServer){
            if ($SearchBase -eq "") {
                $computers += Get-ADComputer -filter $SearchFilter -SearchScope $SearchScope -Server $AdServer -Properties CanonicalName,Description 
            } else {
                $computers += Get-ADComputer -SearchBase $SearchBase -filter $SearchFilter -SearchScope $SearchScope -Server $AdServer -Properties CanonicalName,Description
            }  
        }
	}

    #Sort all computers
    $computers = $computers | Sort-Object -Property CanonicalName

    #Loop through computers and build JSON
    foreach ($computer in $computers)
    {

        $subPath = $computer.canonicalname.replace("/$($computer.name)", "")
    
        $initialCounter = 0
        foreach ($pathItem in $subPath.split("/"))
        {
            $builderPath = $null
            if ($initialCounter -eq 0)
            {
                switch -regex ($computer) {
                    '(DC=(.*),DC=local)|(DC=testcase1,DC=internal)|(DC=int.,DC=internal)|(DC=testcase2,DC=internal)' {
                        $builderPath = "Internal/"
                    }
                    '(DC=[abc]..,DC=internal)|(DC=CONV,DC=internal)' {
                        $builderPath = "Clients A,B, C/"
                    }
                    'DC=[def]..,DC=internal' {
                        $builderPath = "Clients D,E, F/"
                    }
                    'DC=[ghi]..,DC=internal' {
                        $builderPath = "Clients G,H, I/"
                    }
                    'DC=[jkl]..,DC=internal' {
                        $builderPath = "Clients J,K, L/"
                    }
                    'DC=[mno]..,DC=internal' {
                        $builderPath = "Clients M,N, O/"
                    }
                    'DC=[pqr]..,DC=internal' {
                        $builderPath = "Clients P,Q, R/"
                    }
                    'DC=[stu]..,DC=internal' {
                        $builderPath = "Clients S,T, U/"
                    }
                    'DC=[vwx]..,DC=internal' {
                        $builderPath = "Clients V,W, X/"
                    }
                    'DC=[yz]..,DC=internal' {
                        $builderPath = "Clients Y, Z/"
                    }
                }
                

                if($pathItem -match "^(\/...\.internal)|^(...).internal") {
                    [regex]$regex = '^(...)'
                    $customerCode = $pathItem.TrimStart("/")
                    $customerCode = ($regex.Matches($customerCode) | foreach-object {$_.Value}).toUpper()
                    $customerName = ($customers.GetEnumerator() | ? { $_.Key -eq "$customerCode" }).Value

                   $pathItem = "$($customerName) ($($customerCode))"
                }

                $initialCounter++
                $previousPath = $pathItem
            }
            else
            {
                $builderPath = "$($builderPath)/$previousPath".replace('//', '/')
                $previousPath = $pathItem
            }
            if ($pathArray.Contains("$($builderPath)/$pathItem"))
            {
                
            }
            else
            {

                

                if($builderPath -match "^(\/...\.internal)|^(...).internal") {
                    
                    [regex]$regex = '^(...)'
                    $customerCode = $builderPath.TrimStart("/")
                    $customerCode = ($regex.Matches($customerCode) | foreach-object {$_.Value}).toUpper()
                    
                    $customerName = ($customers.GetEnumerator() | ? { $_.Key -eq "$customerCode" }).Value
                    

                   $builderPath = "/$($customerName) ($($customerCode))"
                   
                }

                $array.add((
                        New-Object -TypeName System.Management.Automation.PSObject -Property @{
                            "Type"			    = "Folder";
                            "CredentialsFromParent" = "true";
                            "Path"			    = "$($builderPath)";
                            "Name"			    = "$($pathItem)";
                            "SecureGatewayFromParent" = "True";
                            "RoyalServerFromParent" = "True";
                            "ConnectTaskFromParent" = "True";
                            "DisconnectTaskFromParent" = "True";
                        }
                    )) | Out-Null
                
                $pathArray.add("$($builderPath)/$pathItem") | Out-Null
            }
        }
    
        $type = "RemoteDesktopConnection";
        $portNumber = "3389";
        $useParentCred = "true";
        
        
        $path = "/" + $computer.canonicalname.replace("/$($computer.name)", "");
        
    
        if($path -match "^(\/...\.internal)") {
                [regex]$regex = '^(...)'
                $customerCode = $path.TrimStart("/")
                $customerCode = ($regex.Matches($customerCode) | foreach-object {$_.Value}).toUpper()
                
                $customerName = ($customers.GetEnumerator() | ? { $_.Key -eq "$customerCode" }).Value
                
                $path = $path -replace '\/...\.internal',"/$($customerName) ($($customerCode))"
                
         }

        $array.add((
                New-Object -TypeName System.Management.Automation.PSObject -Property @{
                    "Type" = $type
                    "Port" = $portNumber
                    "Name" = $computer.name;
                    "ComputerName" = $computer.DNSHostName;
                    "Description" = $computer.Description;
                    "credentialName" = $credentialName;
                    "Path" = $path;
                    "ConsoleSession" = $UseAdminConsole;
                    "CredentialsFromParent" = $useParentCred;
                    "ConnectTaskFromParent" = "True";
                    "DisconnectTaskFromParent" = "True";
                    "RoyalServerId" = $RsgId;
                    "SecureGatewayId" = $RsgId;
                }
            )) | Out-Null
    }

    $newarray = $array
    $newarray = ($array)
    $hash = @{ }
    $hash.add("Objects", $newarray)
    return $hash | ConvertTo-Json
}

#Parameters
$OutputPath = "C:\Company\RoyalTS\Company.json"
$AdDomain = "internal.local"

#Get Computer Connections
$royalObjects = Get-RoyalAdComputers -AdDomain $AdDomain -RsgId "GWIDPARM" -IncludeAdTrusts

#Write json output to file
$royalObjects | Out-File -FilePath $OutputPath
