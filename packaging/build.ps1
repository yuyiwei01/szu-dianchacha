#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root '.build'
$dist=Join-Path $root 'dist'
New-Item -ItemType Directory -Force $build | Out-Null
New-Item -ItemType Directory -Force $dist | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files=@('server.ps1','query.ps1','query-functions.ps1') + @(Get-ChildItem "$root/web" -File | ForEach-Object { 'web/' + $_.Name })
$archivePath=Join-Path $build 'app.zip'
if(Test-Path -LiteralPath $archivePath){Remove-Item -LiteralPath $archivePath}
$archive=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($file in $files){ [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $root $file),$file,[IO.Compression.CompressionLevel]::Optimal) | Out-Null }
} finally { $archive.Dispose() }
$hash=(Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0,16)
$source=(Get-Content "$PSScriptRoot/Launcher.cs" -Raw -Encoding UTF8).Replace('__BUILD_ID__',$hash)
$generated=Join-Path $build 'Launcher.cs'
[IO.File]::WriteAllText($generated,$source,(New-Object Text.UTF8Encoding($true)))
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$output=Join-Path $dist 'SZU电查查.exe'
$iconArg=@();if(Test-Path "$PSScriptRoot/app.ico"){$iconArg=@("/win32icon:$PSScriptRoot/app.ico")}
& $compiler /nologo /target:winexe /optimize+ /platform:anycpu "/out:$output" /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Web.Extensions.dll /reference:System.Windows.Forms.dll "/resource:$archivePath,app.zip" @iconArg $generated
if($LASTEXITCODE -ne 0){throw 'Build failed'}
Write-Host "Built $output ($((Get-Item $output).Length) bytes), build $hash"
$sourceZip=Join-Path $dist 'SZU电查查-源码版.zip'
if(Test-Path -LiteralPath $sourceZip){Remove-Item -LiteralPath $sourceZip}
$sourceFiles=@('README.md','LICENSE','.gitignore','.gitattributes','package.json','package-lock.json','启动SZU电查查.bat','launch.ps1','server.ps1','query.ps1','query-functions.ps1')
foreach($dir in @('web','docs','tests','packaging','.github')){
    $sourceFiles+=@(Get-ChildItem (Join-Path $root $dir) -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/](\.runtime|build|__pycache__)[\\/]' } | ForEach-Object { $_.FullName.Substring($root.Length+1).Replace('\','/') })
}
$archive=[IO.Compression.ZipFile]::Open($sourceZip,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($file in $sourceFiles){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $root $file),$file,[IO.Compression.CompressionLevel]::Optimal) | Out-Null}
} finally {$archive.Dispose()}
Write-Host "Built $sourceZip"
