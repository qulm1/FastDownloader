[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z.+_-]*$')][string]$Version = '2.0.0',
    [string]$OutputDir = (Join-Path $PSScriptRoot 'dist')
)
$ErrorActionPreference = 'Stop'

$OutputDir = [IO.Path]::GetFullPath($OutputDir)
$null = New-Item -ItemType Directory -Path $OutputDir -Force
$stage = Join-Path $OutputDir ('FastDownloader-' + $Version + '-stage-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage

# Whitelist packaging: only these items can ever reach a release.
$shipped = @(
    'FastDownload.ps1', 'BatchDownload.ps1', 'StartDownload.cmd', 'BuildRelease.ps1',
    'FastDownloadGui.ps1', 'StartDownloadGui.cmd', 'GuiApp.ps1', 'GuiTasks.ps1', 'GuiView.ps1', 'GuiEngine.cs',
    'README.md', 'README.zh-CN.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md',
    'CODE_OF_CONDUCT.md', 'LICENSE', 'THIRD_PARTY.md', 'TEST_REPORT.md',
    '.gitignore', '.gitattributes', '.editorconfig',
    'docs/ARCHITECTURE.md', 'docs/UI.md', 'docs/GUI.md',
    'tests/NewTestCertificate.ps1', 'tests/TestDownload.mjs', 'tests/TestFaults.mjs', 'tests/TestFeatures.mjs',
    'tests/TestScenarios.mjs', 'tests/TestProtocols.mjs', 'tests/TestLauncher.mjs', 'tests/TestEngineFault.ps1',
    'tests/TestGui.ps1', 'tests/TestGui.mjs', 'tests/TestWpf.ps1', 'tests/TestGuiPackage.ps1',
    'examples/batch.csv', 'examples/batch.json'
)

try {
    foreach ($name in $shipped) {
        $path = Join-Path $PSScriptRoot $name
        if (Test-Path -LiteralPath $path) {
            $target=Join-Path $stage $name
            $null=New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
            Copy-Item -LiteralPath $path -Destination $target
        } else {
            throw ('Missing required release file: ' + $name)
        }
    }

    $sourceZip = Join-Path $OutputDir ('FastDownloader-' + $Version + '-source.zip')
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $sourceZip -Force

    # The portable package adds the pinned engine; the source package never carries it.
    $null=New-Item -ItemType Directory -Path (Join-Path $stage 'bin') -Force
    foreach($name in @('aria2c.exe','AUTHORS','COPYING','ChangeLog','LICENSE.OpenSSL','NEWS','README.html','README.mingw')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('bin/'+$name)) -Destination (Join-Path $stage 'bin')
    }
    $portableZip = Join-Path $OutputDir ('FastDownloader-' + $Version + '.zip')
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $portableZip -Force

    Get-FileHash -LiteralPath $sourceZip, $portableZip -Algorithm SHA256 |
        ForEach-Object { '{0}  {1}' -f $_.Hash.ToLowerInvariant(), (Split-Path $_.Path -Leaf) }
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $expected = $OutputDir.TrimEnd('\') + '\FastDownloader-' + $Version + '-stage-'
    if ($resolved.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
