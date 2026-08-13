## CLEAR Caches and temp variabels 

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
Clear-DnsClientCache
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
