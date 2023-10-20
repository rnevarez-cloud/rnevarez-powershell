Get-ChildItem -Path "c:\webroot\" -Filter *.zip | Where-Object {($_.LastWriteTime -lt (Get-Date).AddDays(-30))} | Remove-Item
