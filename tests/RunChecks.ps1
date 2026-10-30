[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkRoot,
    [switch]$PublicHttps
)
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$work = [IO.Path]::GetFullPath($WorkRoot)
if ([IO.Path]::GetPathRoot($work) -notmatch '^(?i)D:\\$') { throw 'Tests require a D: work directory.' }
if ($work.StartsWith($project.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $work -eq $project) {
    throw 'Test work directory must be outside the source tree.'
}
if (Test-Path -LiteralPath $work) { throw 'Choose a new test work directory; existing evidence is never overwritten.' }
$null = New-Item -ItemType Directory -Path $work
$env:TEST_WORK_ROOT = $work
$env:TEST_CERT_ROOT = Join-Path $work 'tls'
$env:TEST_SKIP_PUBLIC_HTTPS = '1'
if ($PublicHttps) { $env:TEST_SKIP_PUBLIC_HTTPS = '0' }
$checks = New-Object System.Collections.ArrayList
$failed = $false
function Invoke-Check {
    param([string]$Name,[string]$Exe,[string[]]$Arguments)
    $begin = Get-Date
    $status = 'Passed'; $code = 0
    try {
        & $Exe @Arguments | Out-Host
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw ('Exit code ' + $code) }
    } catch {
        $status = 'Failed'; $script:failed = $true
        Write-Warning ($Name + ': ' + $_.Exception.Message)
    }
    [void]$checks.Add([pscustomobject]@{ name=$Name; status=$status; exit_code=$code; seconds=[Math]::Round(((Get-Date)-$begin).TotalSeconds,2) })
}
try {
    $node = (Get-Command node -ErrorAction Stop).Source
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Invoke-Check 'HTTP and restart integrity' $node @((Join-Path $PSScriptRoot 'TestDownload.mjs'))
    Invoke-Check 'Batch and local BT/magnet' $node @((Join-Path $PSScriptRoot 'TestScenarios.mjs'))
    Invoke-Check 'Controlled HTTP faults' $node @((Join-Path $PSScriptRoot 'TestFaults.mjs'))
    Invoke-Check 'Temporary TLS certificate' $pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'NewTestCertificate.ps1'),'-OutputDir',$env:TEST_CERT_ROOT)
    Invoke-Check 'FTP, Metalink and TLS' $node @((Join-Path $PSScriptRoot 'TestProtocols.mjs'))
    Invoke-Check 'Injected engine failure' $ps51 @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'TestEngineFault.ps1'),'-WorkRoot',$work)
    Invoke-Check 'Window engine pause/resume/restart' $node @((Join-Path $PSScriptRoot 'TestWindowEngine.mjs'))
    Invoke-Check 'Offscreen window rendering/layout' $ps51 @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'TestWindowLayout.ps1'),'-WorkRoot',(Join-Path $work 'offscreen'))
    try {
        $package = & (Join-Path $PSScriptRoot 'TestRelease.ps1') -WorkRoot $work
        $env:TEST_PACKAGE_ROOT = $package.portable_root
        [void]$checks.Add([pscustomobject]@{name='Release packages';status='Passed'})
        Invoke-Check 'Exact launcher from portable archive' $node @((Join-Path $PSScriptRoot 'TestLauncher.mjs'))
    } catch {
        $failed = $true
        [void]$checks.Add([pscustomobject]@{name='Release packages / launcher';status='Failed'})
        Write-Warning $_.Exception.Message
    }
} catch {
    $failed = $true
    [void]$checks.Add([pscustomobject]@{name='Environment';status='Failed'})
    Write-Warning $_.Exception.Message
} finally {
    [pscustomobject]@{passed=(-not $failed);public_https= $(if ($PublicHttps) {'Requested'} else {'Explicitly skipped'});checks=@($checks)} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $work 'checks-summary.json') -Encoding UTF8
}
if ($failed) { exit 1 }
Write-Host ('PASS: all requested checks; summary ' + (Join-Path $work 'checks-summary.json'))
exit 0
