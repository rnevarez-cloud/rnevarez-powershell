## Deploy Patch Script
## Author: Ricardo Nevarez
##
## Script used to apply hotfixes from Product Development. Not intended for full cumulative patches or full version upgrades.
##
## Set the $patch variable to the location of the new hotfix. Make sure that the folder structure for the patch matches the folder structure of the web root folder.
##
## For instance, if a script needs to be applied, make sure it is in a folder called "scripts". If a file needs to be applied to the CFC folder, make sure it is in a folder called "cfc".
##
## Example for $patch variable: "C:\Downloads\Eval_3.7\Eval_3.7\*" 
##
## MAKE SURE YOU PUT AN * (asterisk/star) AFTER THE LAST SLASH SO ALL FILES ARE PICKED UP

$folders = Get-ChildItem D:\webroot\ -Exclude "*.zip" -Directory
$patch = "" 

foreach ($folder in $folders)
    { 
    Copy-Item $patch -Destination $folder -force -recurse
    }
