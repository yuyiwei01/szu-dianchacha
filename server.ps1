#Requires -Version 5.1
param([int]$Port=18765, [switch]$OpenBrowser, [string]$BuildId='source', [string]$DataDir=(Join-Path $env:LOCALAPPDATA 'SzuElectricity'))
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. "$PSScriptRoot/query.ps1"
. "$PSScriptRoot/query-functions.ps1"
$utf8=New-Object System.Text.UTF8Encoding($false)
$token=[guid]::NewGuid().ToString('N')
$job=$null; $jobId=$null; $running=$true
$preferencesPath=Join-Path $DataDir 'preferences.json'
function Test-DormPreference($Preference) {
    return $Preference -and $CAMPUSMAP.Contains([string]$Preference.campus) -and $CAMPUSMAP[[string]$Preference.campus].Buildings.Contains([string]$Preference.building) -and ([string]$Preference.room -match '^[0-9A-Za-z\-]{1,16}$')
}
function Read-DormPreference {
    try {
        if(Test-Path -LiteralPath $preferencesPath){
            $preference=Get-Content -LiteralPath $preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if(Test-DormPreference $preference){return $preference}
        }
    } catch {}
    return $null
}
$listener=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,$Port)
$listener.Start()
$origin="http://127.0.0.1:$Port"
if ($OpenBrowser) { Start-Process $origin }
Write-Host "Local electricity dashboard: $origin"
function Send-Response {
    param($Stream,[int]$Status,[string]$Type,[byte[]]$Bytes)
    $reason=switch($Status){200{'OK'} 202{'Accepted'} 400{'Bad Request'} 403{'Forbidden'} 404{'Not Found'} 409{'Conflict'} default{'Internal Server Error'}}
    $header="HTTP/1.1 $Status $reason`r`nContent-Type: $Type`r`nContent-Length: $($Bytes.Length)`r`nConnection: close`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'`r`n`r`n"
    $h=[text.encoding]::ASCII.GetBytes($header); $Stream.Write($h,0,$h.Length); $Stream.Write($Bytes,0,$Bytes.Length)
}
function Get-JobSnapshot {
    if (-not $job) { return @{ state='idle' } }
    $items=@(Receive-Job $job -Keep)
    $result=@($items | Where-Object kind -eq 'result' | Select-Object -Last 1)
    $failure=@($items | Where-Object kind -eq 'error' | Select-Object -Last 1)
    $progress=@($items | Where-Object kind -eq 'progress' | Select-Object -Last 1)
    if ($failure.Count) { return @{ state='error'; message=$failure[0].message; id=$jobId } }
    if ($result.Count) { return @{ state='done'; data=$result[0].data; id=$jobId } }
    if ($job.State -in @('Failed','Stopped','Completed')) { return @{ state='error'; message='查询任务中断，请重新查询。'; id=$jobId } }
    return @{ state='running'; id=$jobId; request=$queryRequest; message=$(if($progress.Count){$progress[0].message}else{'正在准备查询…'}) }
}
try {
    while ($running) {
        $client=$listener.AcceptTcpClient()
        try {
            $stream=$client.GetStream(); $stream.ReadTimeout=5000; $stream.WriteTimeout=5000
            $headerBytes=New-Object System.Collections.Generic.List[byte]
            while ($headerBytes.Count -lt 16384) {
                $b=$stream.ReadByte(); if ($b -lt 0) { throw 'Incomplete request' }; $headerBytes.Add([byte]$b)
                $n=$headerBytes.Count
                if ($n -ge 4 -and $headerBytes[$n-4] -eq 13 -and $headerBytes[$n-3] -eq 10 -and $headerBytes[$n-2] -eq 13 -and $headerBytes[$n-1] -eq 10) { break }
            }
            $lines=([text.encoding]::ASCII.GetString($headerBytes.ToArray())) -split "`r`n"
            $parts=$lines[0] -split ' '; $method=$parts[0]; $path=($parts[1] -split '\?')[0]
            $headers=@{}
            foreach($line in $lines | Select-Object -Skip 1){ if($line -match '^([^:]+):\s*(.*)$'){$headers[$Matches[1].ToLowerInvariant()]=$Matches[2]} }
            if($headers.host -ne "127.0.0.1:$Port" -or ($headers.origin -and $headers.origin -ne $origin)){
                Send-Response $stream 403 'text/plain; charset=utf-8' $utf8.GetBytes('Forbidden'); continue
            }
            $body=''
            if($method -eq 'POST'){
                if($headers['x-local-token'] -ne $token -or $headers['content-type'] -notlike 'application/json*'){Send-Response $stream 403 'text/plain' $utf8.GetBytes('Forbidden');continue}
                $length=0
                if(-not [int]::TryParse([string]$headers['content-length'],[ref]$length) -or $length -lt 0 -or $length -gt 8192){throw 'Invalid request size'}
                $buffer=New-Object byte[] $length; $offset=0
                while($offset -lt $length){$read=$stream.Read($buffer,$offset,$length-$offset);if($read -le 0){throw 'Incomplete body'};$offset+=$read}
                $body=$utf8.GetString($buffer)
            }
            $status=200; $data=$null
            if($method -eq 'GET' -and $path -eq '/api/health'){ $data=@{ app='szu-electricity-local'; version=1; buildId=$BuildId } }
            elseif($method -eq 'GET' -and $path -eq '/api/config'){
                $campuses=@($CAMPUSMAP.Keys | ForEach-Object { @{ name=$_; buildings=@($CAMPUSMAP[$_].Buildings.Keys) } })
                $data=@{ campuses=$campuses; token=$token; preferences=(Read-DormPreference) }
            }
            elseif($method -eq 'POST' -and $path -eq '/api/preferences'){
                $preference=$body | ConvertFrom-Json
                if(-not (Test-DormPreference $preference)){$status=400;$data=@{message='请选择有效宿舍并填写房间号。'}}
                else {
                    $saved=@{campus=[string]$preference.campus;building=[string]$preference.building;room=([string]$preference.room).Trim()}
                    New-Item -ItemType Directory -Force $DataDir | Out-Null
                    [IO.File]::WriteAllText($preferencesPath,($saved | ConvertTo-Json -Compress),$utf8)
                    $data=@{saved=$true;preferences=$saved}
                }
            }
            elseif($method -eq 'GET' -and $path -eq '/api/job'){ $data=Get-JobSnapshot }
            elseif($method -eq 'POST' -and $path -eq '/api/query'){
                if($job -and $job.State -eq 'Running'){ $status=409; $data=@{message='已有查询正在进行，请等待或取消。'} }
                else {
                    $inputData=$body | ConvertFrom-Json
                    $queryRequest=$inputData
                    if($job){Remove-Job $job -Force}
                    $jobId=[guid]::NewGuid().ToString('N')
                    $job=Start-Job -ArgumentList $PSScriptRoot,$inputData -ScriptBlock {
                        param($root,$request)
                        try { . "$root/query.ps1"; . "$root/query-functions.ps1"; Invoke-ElectricityQuery $request }
                        catch { [pscustomobject]@{ kind='error'; message=$_.Exception.Message } }
                    }
                    $status=202; $data=@{id=$jobId;state='running'}
                }
            }
            elseif($method -eq 'POST' -and $path -eq '/api/cancel'){
                if($job){Stop-Job $job;Remove-Job $job -Force;$job=$null}; $data=@{state='idle'}
            }
            elseif($method -eq 'POST' -and $path -eq '/api/stop'){ $running=$false; $data=@{state='stopped'} }
            elseif($method -eq 'GET' -and $path -in @('/','/index.html','/style.css','/app.js','/model.js','/chart.js','/favicon.svg')){
                $file=if($path -eq '/'){'index.html'}else{$path.TrimStart('/')}
                $type=switch([IO.Path]::GetExtension($file)){'.html'{'text/html; charset=utf-8'} '.css'{'text/css; charset=utf-8'} '.js'{'text/javascript; charset=utf-8'} '.svg'{'image/svg+xml'} }
                Send-Response $stream 200 $type ([IO.File]::ReadAllBytes((Join-Path "$PSScriptRoot/web" $file))); continue
            }
            else { $status=404; $data=@{message='页面不存在。'} }
            Send-Response $stream $status 'application/json; charset=utf-8' $utf8.GetBytes(($data | ConvertTo-Json -Depth 12 -Compress))
        } catch {
            try{Send-Response $stream 400 'application/json; charset=utf-8' $utf8.GetBytes('{"message":"请求无效，请重新打开页面。"}')}catch{}
        } finally { $client.Close() }
    }
} finally {
    if($job){Stop-Job $job;Remove-Job $job -Force}
    $listener.Stop()
}
