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
    'README.md', 'README.zh-CN.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md',
    'CODE_OF_CONDUCT.md', 'LICENSE', 'THIRD_PARTY.md', 'TEST_REPORT.md',
    '.gitignore', '.gitattributes', '.editorconfig',
    'docs', 'tests', 'examples'
)

try {
    foreach ($name in $shipped) {
        $path = Join-Path $PSScriptRoot $name
        if (Test-Path -LiteralPath $path) {
            Copy-Item -LiteralPath $path -Destination $stage -Recurse
        } else {
            Write-Warning ('Skipping missing item: ' + $name)
        }
    }

    $sourceZip = Join-Path $OutputDir ('FastDownloader-' + $Version + '-source.zip')
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $sourceZip -Force

    # The portable package adds the pinned engine; the source package never carries it.
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin') -Destination $stage -Recurse
    $portableZip = Join-Path $OutputDir ('FastDownloader-' + $Version + '.zip')
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $portableZip -Force

    Get-FileHash -LiteralPath $sourceZip, $portableZip -Algorithm SHA256 |
        ForEach-Object { '{0}  {1}' -f $_.Hash.ToLowerInvariant(), (Split-Path $_.Path -Leaf) }
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $expected = $OutputDir.TrimEnd('\') + '\FastDownloader-' + $Version + '-stage-'
    if ($resolved.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
