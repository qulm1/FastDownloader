param([string]$WorkRoot=(Join-Path $env:TEMP 'FastDownloaderGuiTests'))
$ErrorActionPreference='Stop'
$root=Join-Path $WorkRoot ('gui-'+[Guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'TestWpf.ps1') -WorkRoot $root
