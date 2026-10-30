[CmdletBinding()]
param([string]$OutputDir = 'D:\softwere\Releases')
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($OutputDir)) -notmatch '^(?i)D:\\$') { throw 'Release output must be on D:.' }
$null = New-Item -ItemType Directory -Path $OutputDir -Force
$stage = Join-Path $OutputDir ('FastDownloader-2.0-stage-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage
try {
    $sourceFiles = @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','BuildRelease.ps1',
        'DownloadWindow.ps1','WindowEngine.cs','StartDownloadWindow.cmd','WindowLayout.ps1','DownloadDialog.ps1','DesktopStyles.cs','WindowLauncher.cs','BuildWindow.ps1',
        'README.md','TEST_REPORT.md','WINDOW_GUIDE.md','LICENSE','THIRD_PARTY.md','.gitignore','CONTRIBUTING.md','SECURITY.md',
        'examples/batch.csv','examples/batch.json',
        'tests/NewTestCertificate.ps1','tests/TestDownload.mjs','tests/TestEngineFault.ps1',
        'tests/TestFaults.mjs','tests/TestLauncher.mjs','tests/TestProtocols.mjs','tests/TestScenarios.mjs',
        'tests/RunChecks.ps1','tests/TestRelease.ps1','tests/TestWindowEngine.ps1','tests/TestWindowEngine.mjs','tests/WindowFixture.mjs',
        'tests/TestWindowFlow.ps1','tests/TestWindowLayout.ps1')
    foreach ($name in $sourceFiles) {
        $target = Join-Path $stage $name
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $target
    }
    $source = Join-Path $OutputDir 'FastDownloader-2.0-source.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $source -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $stage 'bin') -Force
    foreach ($name in @('aria2c.exe','AUTHORS','COPYING','ChangeLog','LICENSE.OpenSSL','NEWS','README.html','README.mingw')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('bin/' + $name)) -Destination (Join-Path $stage 'bin')
    }
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'BuildWindow.ps1') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Window launcher build failed.' }
    $portable = Join-Path $OutputDir 'FastDownloader-2.0.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $portable -Force
    Get-FileHash -LiteralPath $source,$portable -Algorithm SHA256
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $expected = [IO.Path]::GetFullPath($OutputDir).TrimEnd('\') + '\FastDownloader-2.0-stage-'
    if ($resolved.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
