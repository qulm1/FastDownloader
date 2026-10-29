[CmdletBinding()]
param([string]$OutputDir = 'D:\softwere\Releases')
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($OutputDir)) -notmatch '^(?i)D:\\$') { throw 'Release output must be on D:.' }
$null = New-Item -ItemType Directory -Path $OutputDir -Force
$stage = Join-Path $OutputDir ('FastDownloader-2.0-stage-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage
try {
    foreach ($name in @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','BuildRelease.ps1','README.md','TEST_REPORT.md','LICENSE','THIRD_PARTY.md','.gitignore','tests','examples')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $stage -Recurse
    }
    $source = Join-Path $OutputDir 'FastDownloader-2.0-source.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $source -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin') -Destination $stage -Recurse
    $portable = Join-Path $OutputDir 'FastDownloader-2.0.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $portable -Force
    Get-FileHash -LiteralPath $source,$portable -Algorithm SHA256
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $expected = [IO.Path]::GetFullPath($OutputDir).TrimEnd('\') + '\FastDownloader-2.0-stage-'
    if ($resolved.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
