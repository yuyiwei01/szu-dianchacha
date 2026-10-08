#Requires -Version 5.1
try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch {}
$script:GB = [System.Text.Encoding]::GetEncoding('gb2312')

function Read-SimsPage {
    param([string]$Html, [int]$Type)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($tr in [regex]::Matches($Html, '(?is)<tr\b[^>]*>(.*?)</tr>')) {
        $cells = @([regex]::Matches($tr.Groups[1].Value, '(?is)<td\b[^>]*>(.*?)</td>') | ForEach-Object {
            [System.Net.WebUtility]::HtmlDecode(([regex]::Replace($_.Groups[1].Value, '<[^>]+>', ''))).Trim()
        })
        $count = if ($Type -eq 2) { 6 } else { 7 }
        if ($cells.Count -ne $count -or $cells[0] -notmatch '^\d+$') { continue }
        try {
            $date = [datetime]::Parse($cells[-1], [cultureinfo]::InvariantCulture)
            $row = [ordered]@{ no=[int]$cells[0]; room=$cells[1]; date=$date.ToString('yyyy-MM-dd HH:mm:ss') }
            if ($Type -eq 2) {
                $row.remain=[double]::Parse($cells[2], [cultureinfo]::InvariantCulture)
                $row.used=[double]::Parse($cells[3], [cultureinfo]::InvariantCulture)
                $row.bought=[double]::Parse($cells[4], [cultureinfo]::InvariantCulture)
            } else {
                $row.buyer=$cells[2]; $row.buyType=$cells[3]
                $row.amount=[double]::Parse($cells[4], [cultureinfo]::InvariantCulture)
                $row.money=[double]::Parse($cells[5], [cultureinfo]::InvariantCulture)
            }
            $rows.Add([pscustomobject]$row)
        } catch { throw '记录格式发生变化，无法可靠解析。请重试或检查学校查询页面。' }
    }
    $text = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($Html, '<[^>]+>', ' '))
    $m = [regex]::Match($text, '共找到\s*(\d+)\s*条数据\s*[,，]\s*每页显示\s*(\d+)\s*条记录\s*[,，]\s*当前页\s*[:：]\s*(\d+)\s*/\s*(\d+)')
    if (-not $m.Success) { throw '未能识别分页信息，已停止查询，避免展示不完整数据。' }
    return [pscustomobject]@{ rows=@($rows.ToArray()); total=[int]$m.Groups[1].Value; page=[int]$m.Groups[3].Value; pages=[Math]::Max(1,[int]$m.Groups[4].Value) }
}

function Invoke-SimsPost {
    param([string]$Url, [hashtable]$Form, $Session)
    # The original SIMS accepts UTF-8 percent-encoded form values, with GB2312 responses.
    $encoded = ($Form.GetEnumerator() | ForEach-Object { [uri]::EscapeDataString($_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value) }) -join '&'
    for ($attempt=0; $attempt -lt 2; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method POST -Body ([text.encoding]::ASCII.GetBytes($encoded)) -ContentType 'application/x-www-form-urlencoded' -WebSession $Session -UseBasicParsing -TimeoutSec 20
            return $script:GB.GetString($response.RawContentStream.ToArray())
        } catch { if ($attempt -eq 1) { throw '学校服务器请求失败或超时，请检查校园网 / VPN 后重试。' } }
    }
}

function Get-CompleteRecords {
    param([int]$Type, [hashtable]$Form, [scriptblock]$Fetch)
    $all = New-Object System.Collections.Generic.List[object]
    $seen = @{}; $pages=1; $total=-1
    for ($page=1; $page -le $pages; $page++) {
        $Form.pageNo=[string]$page; $Form.type=[string]$Type
        $parsed = Read-SimsPage (& $Fetch $Form) $Type
        if ($page -eq 1) { $pages=$parsed.pages; $total=$parsed.total }
        if ($pages -gt 1000) { throw '记录页数过多，请缩短查询时间范围。' }
        if (($total -gt 0 -and $parsed.page -ne $page) -or $parsed.total -ne $total -or $parsed.pages -ne $pages) { throw '查询期间数据或分页发生变化，请重新查询。' }
        foreach ($row in $parsed.rows) {
            if ($seen.ContainsKey($row.no)) { throw '服务器返回了重复页，已停止查询，避免错误合计。' }
            $seen[$row.no]=$true; $all.Add($row)
        }
        [pscustomobject]@{ kind='progress'; message="$(if($Type -eq 2){'用电记录'}else{'购电记录'})：已读取 $page / $pages 页，共 $($all.Count) 条" }
    }
    if ($all.Count -ne $total) { throw "记录不完整：服务器声明 $total 条，实际读取 $($all.Count) 条。请重新查询。" }
    [pscustomobject]@{ kind='records'; type=$Type; rows=@($all.ToArray() | Sort-Object date,no); total=$total; pages=$pages }
}

function Invoke-ElectricityQuery {
    param($InputData)
    $campus=[string]$InputData.campus; $building=[string]$InputData.building; $room=([string]$InputData.room).Trim()
    if (-not $CAMPUSMAP.Contains($campus)) { throw '请选择有效校区。' }
    $config=$CAMPUSMAP[$campus]
    if (-not $config.Buildings.Contains($building)) { throw '请选择有效楼栋。' }
    if ($room -notmatch '^[0-9A-Za-z\-]{1,16}$') { throw '请填写正确的房间号，例如 101。' }
    $begin=[datetime]::ParseExact([string]$InputData.begin, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $end=[datetime]::ParseExact([string]$InputData.end, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    if ($begin -gt $end -or ($end-$begin).TotalDays -gt 1096) { throw '请选择有效日期范围，单次查询最多三年。' }
    if ($end.Date -gt (Get-Date).Date) { throw '结束日期不能晚于今天。' }
    [pscustomobject]@{ kind='progress'; message='正在连接校园查询服务器…' }
    $base=$null; $session=$null
    foreach ($ip in @('192.168.84.3', $config.Client) | Select-Object -Unique) {
        try {
            $url="http://${ip}:9090/cgcSims"
            $null=Invoke-WebRequest "$url/" -SessionVariable candidate -UseBasicParsing -TimeoutSec 8
            $base=$url; $session=$candidate; break
        } catch {}
    }
    if (-not $base) { throw '无法连接校园电费系统，请连接校园网或校内 VPN 后重试。' }
    $html=Invoke-SimsPost "$base/login.do" @{ client=$config.Client; buildingId=$config.Buildings[$building]; buildingName=$building; roomName=$room; select=' 查询 ' } $session
    $roomId=$null
    foreach ($tag in [regex]::Matches($html, '(?is)<input\b[^>]*>')) {
        if ($tag.Value -match 'name\s*=\s*["'']roomId["'']' -and $tag.Value -match 'value\s*=\s*["'']([^"'']+)["'']') { $roomId=$Matches[1].Trim(); break }
    }
    if (-not $roomId) { throw '没有找到该房间，请核对校区、楼栋和房间号。' }
    $form=@{ hiddenType='0'; isHost='0'; beginTime=$begin.ToString('yyyy-MM-dd'); endTime=$end.ToString('yyyy-MM-dd'); client=$config.Client; roomId=$roomId; roomName=$room; building=$building }
    $usage=$null; $purchases=$null
    foreach ($type in @(2,1)) {
        Get-CompleteRecords $type $form { param($f) Invoke-SimsPost "$base/selectList.do" $f $session } | ForEach-Object {
            if ($_.kind -eq 'progress') { $_ }
            elseif ($type -eq 2) { $usage=$_ } else { $purchases=$_ }
        }
    }
    [pscustomobject]@{ kind='result'; data=[pscustomobject]@{
        campus=$campus; building=$building; room=$room; begin=$begin.ToString('yyyy-MM-dd'); end=$end.ToString('yyyy-MM-dd')
        fetchedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); usage=@($usage.rows); purchases=@($purchases.rows)
        usagePages=$usage.pages; purchasePages=$purchases.pages; complete=$true
    } }
}
