#Requires -Version 5.1
$ErrorActionPreference='Stop'
try {
    for($port=18765;$port -lt 18775;$port++){
        try {
            $health=Invoke-RestMethod "http://127.0.0.1:$port/api/health" -TimeoutSec 1
            if($health.app -eq 'szu-electricity-local'){Start-Process "http://127.0.0.1:$port";exit}
        } catch {}
        $probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$port)
        try{$probe.Start();$probe.Stop();break}catch{}
    }
    if($port -ge 18775){throw 'No available local port.'}
    $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $logDir=Join-Path $env:LOCALAPPDATA 'SzuElectricity';New-Item -ItemType Directory -Force $logDir | Out-Null
    Start-Process $shell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\server.ps1`" -Port $port -OpenBrowser" -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'server.log') -RedirectStandardError (Join-Path $logDir 'error.log')
    for($i=0;$i -lt 30;$i++){
        Start-Sleep -Milliseconds 200
        try{ $health=Invoke-RestMethod "http://127.0.0.1:$port/api/health" -TimeoutSec 1; if($health.app -eq 'szu-electricity-local'){exit} }catch{}
    }
    throw "Startup failed. See $logDir\error.log"
} catch { Write-Host $_.Exception.Message; Read-Host 'Press Enter to close'; exit 1 }
