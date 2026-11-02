[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'FastDownloader.exe' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /reference:System.Windows.Forms.dll ("/out:" + [IO.Path]::GetFullPath($OutputPath)) (Join-Path $PSScriptRoot 'Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'GUI launcher compilation failed.' }