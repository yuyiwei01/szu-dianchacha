#Requires -Version 5.1
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../query-functions.ps1"
function Assert($Condition,$Message){if(-not $Condition){throw "FAIL: $Message"}}
function Page($No,$Current=1,$Pages=1,$Total=1,$Type=2) {
    $cells=if($Type -eq 2){"<td>$No</td><td>101</td><td>-2.5</td><td>100.25</td><td>97.75</td><td>2026-09-01 23:59:00.0</td>"}else{"<td>$No</td><td>101</td><td>张&amp;三</td><td>微信</td><td>142.86</td><td>100</td><td>2026-09-01 12:30:00.0</td>"}
    "<table><tr class='record'>$cells</tr></table>共找到&nbsp;$Total&nbsp;条数据, 每页显示19条记录, 当前页: $Current / $Pages"
}
$p=Read-SimsPage (Page 1) 2
Assert ($p.rows[0].remain -eq -2.5) 'negative balances parsed'
$p=Read-SimsPage (Page 1 1 1 1 1) 1
Assert ($p.rows[0].buyer -eq '张&三') 'HTML entities decoded'
Assert ($p.rows[0].date -eq '2026-09-01 12:30:00') 'purchase time preserved'
$out=@(Get-CompleteRecords 2 @{} {param($f) Page ([int]$f.pageNo) ([int]$f.pageNo) 3 3})
$records=$out | Where-Object kind -eq 'records'
Assert ($records.total -eq 3 -and $records.rows.Count -eq 3) 'all pages fetched'
$caught=$false;try{Get-CompleteRecords 2 @{} {param($f) Page 1 ([int]$f.pageNo) 2 2} | Out-Null}catch{$caught=$true};Assert $caught 'duplicate pages rejected'
$caught=$false;try{Get-CompleteRecords 2 @{} {param($f) Page 1 1 1 2} | Out-Null}catch{$caught=$true};Assert $caught 'incomplete results rejected'
$caught=$false;try{Read-SimsPage '<html>session expired</html>' 2 | Out-Null}catch{$caught=$true};Assert $caught 'unknown page rejected'
$p=Read-SimsPage '共找到0条数据, 每页显示19条记录, 当前页: 1 / 0' 2
Assert ($p.rows.Count -eq 0 -and $p.pages -eq 1) 'empty upstream pagination handled'
Write-Host 'PASS: HTML parsing, all pages, duplicate detection, completeness, empty results'
