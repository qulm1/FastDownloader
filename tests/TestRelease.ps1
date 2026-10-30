param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $WorkRoot ('release-fixture-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture -Force
foreach ($name in @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','BuildRelease.ps1',
    'README.md','TEST_REPORT.md','LICENSE','THIRD_PARTY.md','.gitignore','CONTRIBUTING.md','SECURITY.md','tests','examples','bin')) {
    Copy-Item -LiteralPath (Join-Path $project $name) -Destination $fixture -Recurse
}
# Canary files exist only in this fixture, never in the developer's real state/bin.
$null = New-Item -ItemType Directory -Path (Join-Path $fixture 'state/jobs') -Force
foreach ($name in @('cookies.txt','state/jobs/private.json','bin/private-cookie.txt','tests/private-test.key')) {
    Set-Content -LiteralPath (Join-Path $fixture $name) -Value 'PRIVATE-TEST-CANARY' -Encoding ASCII
}
$out = Join-Path $WorkRoot ('packages-' + [Guid]::NewGuid().ToString('N'))
& (Join-Path $fixture 'BuildRelease.ps1') -OutputDir $out | Out-Host
if (-not (Test-Path -LiteralPath (Join-Path $out 'FastDownloader-2.0.zip'))) { throw 'Portable archive missing' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($name in @('FastDownloader-2.0-source.zip','FastDownloader-2.0.zip')) {
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $out $name))
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
        if ($names | Where-Object { $_ -match '(?i)(^|/)(state|downloads|\.git)/|private-cookie|private-test|cookies\.txt|\.pem$|\.key$' }) {
            throw ('Private fixture data was included in ' + $name)
        }
        foreach ($required in @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','LICENSE','THIRD_PARTY.md','tests/RunChecks.ps1')) {
            if ($required -notin $names) { throw ('Missing package file: ' + $required) }
        }
        if ($name -like '*source*') {
            if ($names | Where-Object { $_ -like 'bin/*' }) { throw 'Source archive must not contain bundled binaries' }
        } else {
            foreach ($required in @('bin/aria2c.exe','bin/COPYING','bin/LICENSE.OpenSSL','bin/AUTHORS')) {
                if ($required -notin $names) { throw ('Missing portable dependency/license: ' + $required) }
            }
        }
    } finally { $zip.Dispose() }
}
$portable = Join-Path $WorkRoot ('portable test-' + [Guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath (Join-Path $out 'FastDownloader-2.0.zip') -DestinationPath $portable
foreach ($name in @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','bin/aria2c.exe')) {
    if ((Get-FileHash -LiteralPath (Join-Path $project $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $portable $name)).Hash) {
        throw ('Portable content changed: ' + $name)
    }
}
$result = [pscustomobject]@{ passed=$true; portable_root=$portable; package_dir=$out }
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkRoot 'release-check.json') -Encoding UTF8
Write-Host 'PASS: release whitelist, licenses, source/portable split, private canaries and byte identity'
return $result
