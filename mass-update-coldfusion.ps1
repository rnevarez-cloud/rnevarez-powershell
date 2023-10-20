## Updating ColdFusion Script ##

##########################
## Installing CF Update ##
##########################

$hotfix = "" ## Filepath Required 
$propertiesPath = "C:\Downloads\install.properties" ##Filepath Required
$instances = (Get-ChildItem F:\CF2018\ -Filter web_* -Directory | Select-Object -ExpandProperty Name) -join ","
$properties = @"
INSTALLER_UI=SILENT
USER_INSTALL_DIR=F:/CF2018/
DOC_ROOT=F:/CF2018/CFUSION/WWWROOT
#THE FOLLOWING APPLIES ONLY TO MULTI SERVER SCENARIOS.
INSTANCE_LIST=$($instances)
"@

Write-Output $properties | Out-File -Filepath $propertiesPath

F:\CF2018\jre\bin\java.exe -jar $hotfix -I SILENT -F $propertiesPath

###############################
## Install .jar hotfix files ##
###############################

$folders = Get-ChildItem F:\CF2018\ -Filter web_* -Directory

foreach ($folder in $folders)
    {
        $filepath = Join-Path "F:\CF2018\$($folder)" "/lib/updates"
        Copy-Item -Path "C:\Downloads\CFJAR\*" -Destination $filepath
    }

##############################
##  Restart Services  ##
##############################

$SONIS = Get-Service "ColdFusion **** Application Server *"
$SONIS | %{ restart-service $_ }
