function Set-RDS {
   
    param(
        [Parameter(Mandatory)]
        [string]$customer,

        [Parameter(Mandatory)]
        [string]$ClientCode,

        [ValidateNotNullOrEmpty()]
        [string]$ComputerName = [System.Net.Dns]::GetHostByName($env:computerName).HostName,

        [Parameter(Mandatory)]
        [string]$Datacenter,

        [Parameter(Mandatory)]
        [string]$Cert,

        [Parameter(Mandatory)]
        [SecureString]$Password

    )

Enter-PSSession $ComputerName

##Name of customer
$customer = $customer + " RemoteApps"
$AppURL = "$($ClientCode.ToLower())apps.contosocloud.com"

Import-Module RemoteDesktop
Import-Module ActiveDirectory

##Setting up Remote Desktop Services
New-RDSessionDeployment -ConnectionBroker $ComputerName -WebAccessServer $ComputerName -SessionHost $ComputerName

Add-RDServer $ComputerName -Server $ComputerName -Role "RDS-GATEWAY" -ConnectionBroker $ComputerName
Set-RDDeploymentGatewayConfiguration -GatewayMode "Custom" -GatewayExternalFQDN $AppURL -BypassLocal $True -UseCachedCredentials $True -LogonMethod Password -Force

Add-RDServer $ComputerName -Server $ComputerName -Role "RDS-LICENSING" -ConnectionBroker $ComputerName
Set-RDLicenseConfiguration -LicenseServer $ComputerName -Mode PerUser -ConnectionBroker $ComputerName -Force

New-RDSessionCollection -CollectionName $customer -SessionHost $ComputerName -ConnectionBroker $ComputerName
Set-RDSessionCollectionConfiguration -CollectionName $customer -UserGroup "$($ClientCode)\CONTOSO RDS Users","$($ClientCode)\$($ClientCode) RDS Users" -ConnectionBroker $ComputerName

Set-RDWorkspace -Name $customer

##Setting Certificates
Set-RDCertificate -Role RDGateway -ImportPath $Cert -Password $Password -ConnectionBroker $ComputerName -Force
Set-RDCertificate -Role RDWebAccess -ImportPath $Cert -Password $Password -ConnectionBroker $ComputerName -Force
Set-RDCertificate -Role RDRedirector -ImportPath $Cert -Password $Password -ConnectionBroker $ComputerName -Force 
Set-RDCertificate -Role RDPublishing -ImportPath $Cert -Password $Password -ConnectionBroker $ComputerName -Force

##Setting up RDS access groups
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "$($ClientCode)\CONTOSO RDS Users"
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "$($ClientCode)\$($ClientCode) RDS Users"

##Setting up RDWeb
Install-Module -Name RDWebClientManagement
Install-RDWebClientPackage
Import-RDWebClientBrokerCert $cert -password $password
Publish-RDWebClientPackage -Type Production -Latest

##Collecting SIDs of CONTOSO and Client RDS Group
$ClientRDSGroup = (Get-ADGroup "$($ClientCode) RDS Users").SID.Value
$CONTOSORDSGroup = (Get-ADGroup "CONTOSO RDS Users").SID.Value

##Adding Remote Server Groups for RADIUS
##NOTE: Client RADIUS server group IP will need to be edited once RADIUS is set up on their end
if ($Datacenter = "DAL10") {
netsh nps add remoteserver remoteservergroup = "CONTOSO RADIUS" address = "192.168.1.1" 
} elseif ($Datacenter = "DC04") {
netsh nps add remoteserver remoteservergroup = "CONTOSO RADIUS" address = "192.168.1.2" 
}
netsh nps add remoteserver remoteservergroup = "$($ClientCode) RADIUS" address = "127.0.0.1"


##Connection Request Policy Setup
##Adjusting sequencing of default CRPs
netsh nps set crp name = "TS GATEWAY AUTHORIZATION POLICY" processingorder = "3"
netsh nps set crp name = "Use Windows authentication for all users" processingorder = "4"

##Adding new CRPs for CONTOSO
netsh nps add crp name = "$($ClientCode) Users" state = "ENABLE" processingorder = "1" policysource = "1" conditionid = "0x1" conditiondata = "$($ClientCode)\\.+"  profileid = "0x1029" profiledata = "$($ClientCode) RADIUS" profileid = "0x1025" profiledata = "2"
netsh nps add crp name = "CONTOSO Users" state = "ENABLE" processingorder = "2" policysource = "1" conditionid = "0x1" conditiondata = "CONTOSO\\.+" profileid = "0x1029" profiledata = "CONTOSO RADIUS" profileid = "0x1025" profiledata = "2"

##Network Policy Setup
##Adjusting sequencing of default NPs
netsh nps set np name = "Connections to other access servers" processingorder = "6"
netsh nps set np name = "Connections to Microsoft Routing and Remote Access server" processingorder = "5"
netsh nps set np name = "-- RDG Marker Policy {985F7B54-FCE8-4f55-AEBF-DF8827A44068} --" processingorder = "4"
netsh nps set np name = "RDG_CAP_AllUsers" processingorder = "3"

##Adding new NPs for CONTOSO
netsh nps add np name = "$($ClientCode) Users" state = "ENABLE" processingorder = "1" policysource = "1" conditionid = "0x1fb5" conditiondata = $ClientRDSGroup profileid = "0x1009" profiledata = "0x1" profiledata = "0x2" profiledata = "0x3" profiledata = "0x9" profiledata = "0x4" profiledata = "0x7" profiledata = "0xa" profileid = "0x1025" profiledata = "2"
netsh nps add np name = "CONTOSO Users" state = "ENABLE" processingorder = "2" policysource = "1" conditionid = "0x1fb5" conditiondata = $CONTOSORDSGroup profileid = "0x1009" profiledata = "0x1" profiledata = "0x2" profiledata = "0x3" profiledata = "0x9" profi
ledata = "0x4" profiledata = "0x7" profiledata = "0xa" profileid = "0x1025" profiledata = "2" 

##Adding new RAPs for CONTOSO
New-Item -Path RDS:\GatewayServer\RAP -Name "CONTOSO RAP" -UserGroups "CONTOSO RDS Users@$($ClientCode).CONTOSO" -ComputerGroupType "2"
New-Item -Path RDS:\GatewayServer\RAP -Name "$($ClientCode) RAP" -UserGroups "$($ClientCode) RDS Users@$($ClientCode).CONTOSO" -ComputerGroupType "2"

##Restart server to finish setup
Restart-Computer -Force

}
