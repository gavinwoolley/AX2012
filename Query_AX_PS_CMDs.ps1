Get-Command *ax*
Where-Object {$_.CommandType -eq "Cmdlet"}
Select-Object Name,@{Name="Assembly"; Expression={Split-Path $_.DLL -Leaf}}
Sort-Object Assembly,Name