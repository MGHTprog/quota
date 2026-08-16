$ErrorActionPreference = 'Stop'

$projectDir = Join-Path $PSScriptRoot 'Quota.Windows'
$outputDir = Join-Path $PSScriptRoot 'dist'
$compiler = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path $compiler)) {
    $compiler = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $compiler)) {
    throw 'The .NET Framework C# compiler was not found. Enable .NET Framework 4.8.'
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$sourceIcon = Join-Path (Split-Path $PSScriptRoot) 'Sources\Quota\Resources\MenuBarIcon.png'
$iconPath = Join-Path $outputDir 'Quota.Windows.ico'
$png = [System.IO.File]::ReadAllBytes($sourceIcon)
$stream = [System.IO.File]::Create($iconPath)
$writer = New-Object System.IO.BinaryWriter($stream)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]1)
    $writer.Write([Byte]32)
    $writer.Write([Byte]32)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$png.Length)
    $writer.Write([UInt32]22)
    $writer.Write($png)
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}
$sources = Get-ChildItem -Path $projectDir -Filter '*.cs' | ForEach-Object { $_.FullName }
$references = @(
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Net.Http.dll',
    '/reference:System.Security.dll',
    '/reference:System.Web.Extensions.dll',
    '/reference:System.Windows.Forms.dll'
)

& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /win32manifest:"$projectDir\app.manifest" /win32icon:"$iconPath" `
    /main:Quota.Windows.Program /out:"$outputDir\Quota.Windows.exe" $references $sources
if ($LASTEXITCODE -ne 0) { throw "Quota.Windows.exe compilation failed with exit code $LASTEXITCODE" }

Copy-Item -LiteralPath "$projectDir\Quota.Windows.exe.config" -Destination "$outputDir\Quota.Windows.exe.config" -Force

& $compiler /nologo /target:exe /platform:anycpu /optimize+ /main:Quota.Windows.MappingTests `
    /out:"$outputDir\Quota.Windows.Tests.exe" $references $sources
if ($LASTEXITCODE -ne 0) { throw "Quota.Windows.Tests.exe compilation failed with exit code $LASTEXITCODE" }

& "$outputDir\Quota.Windows.Tests.exe"
if ($LASTEXITCODE -ne 0) { throw "Mapping tests failed with exit code $LASTEXITCODE" }

Write-Host "Build completed: $outputDir\Quota.Windows.exe"
