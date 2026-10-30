param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $WorkRoot ('release-fixture-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture -Force
foreach ($name in @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','BuildRelease.ps1',
    'DownloadWindow.ps1','WindowEngine.cs','StartDownloadWindow.cmd','WindowLayout.ps1','DownloadDialog.ps1','DesktopStyles.cs','WindowLauncher.cs','BuildWindow.ps1',
    'README.md','TEST_REPORT.md','WINDOW_GUIDE.md','LICENSE','THIRD_PARTY.md','.gitignore','CONTRIBUTING.md','SECURITY.md','tests','examples','bin')) {
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
        foreach ($required in @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','DownloadWindow.ps1','WindowEngine.cs','WindowLayout.ps1','DownloadDialog.ps1','DesktopStyles.cs','WindowLauncher.cs','BuildWindow.ps1','StartDownloadWindow.cmd','LICENSE','THIRD_PARTY.md','tests/RunChecks.ps1','tests/TestWindowFlow.ps1','tests/TestWindowLayout.ps1')) {
            if ($required -notin $names) { throw ('Missing package file: ' + $required) }
        }
        if ($name -like '*source*') {
            if ($names | Where-Object { $_ -like 'bin/*' }) { throw 'Source archive must not contain bundled binaries' }
        } else {
            foreach ($required in @('bin/aria2c.exe','bin/FastDownloader.exe','bin/COPYING','bin/LICENSE.OpenSSL','bin/AUTHORS')) {
                if ($required -notin $names) { throw ('Missing portable dependency/license: ' + $required) }
            }
        }
    } finally { $zip.Dispose() }
}
$portable = Join-Path $WorkRoot ('portable test-' + [Guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath (Join-Path $out 'FastDownloader-2.0.zip') -DestinationPath $portable
foreach ($name in @('FastDownload.ps1','BatchDownload.ps1','StartDownload.cmd','DownloadWindow.ps1','WindowEngine.cs','WindowLayout.ps1','DownloadDialog.ps1','DesktopStyles.cs','WindowLauncher.cs','BuildWindow.ps1','StartDownloadWindow.cmd','bin/aria2c.exe')) {
    if ((Get-FileHash -LiteralPath (Join-Path $project $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $portable $name)).Hash) {
        throw ('Portable content changed: ' + $name)
    }
}
$runtimeReport=Join-Path $WorkRoot 'packaged-window-runtime.txt'
$runtimeState=Join-Path $WorkRoot 'runtime state'
$runtimeOutput=Join-Path $WorkRoot 'runtime downloads'
$runtimeArgs='--check --state-dir "'+$runtimeState+'" --download-dir "'+$runtimeOutput+'" --check-report "'+$runtimeReport+'"'
$runtime=Start-Process -FilePath (Join-Path $portable 'bin/FastDownloader.exe') -ArgumentList $runtimeArgs -WindowStyle Hidden -Wait -PassThru
if($runtime.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $runtimeReport) -or (Get-Content -LiteralPath $runtimeReport -Raw) -notlike 'PASS:*') { throw 'Packaged window runtime check failed.' }
$missingRoot=Join-Path $WorkRoot ('missing window files-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $missingRoot 'bin')
Copy-Item -LiteralPath (Join-Path $portable 'bin/FastDownloader.exe') -Destination (Join-Path $missingRoot 'bin/FastDownloader.exe')
$missingReport=Join-Path $WorkRoot 'missing-window-runtime.txt'
$missing=Start-Process -FilePath (Join-Path $missingRoot 'bin/FastDownloader.exe') -ArgumentList ('--check --check-report "'+$missingReport+'"') -WindowStyle Hidden -Wait -PassThru
if($missing.ExitCode -ne 1 -or -not (Test-Path -LiteralPath $missingReport) -or (Get-Content -LiteralPath $missingReport -Raw) -notlike 'FAIL:*') { throw 'Missing window resources were not rejected.' }
$result = [pscustomobject]@{ passed=$true; portable_root=$portable; package_dir=$out }
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkRoot 'release-check.json') -Encoding UTF8
Write-Host 'PASS: release whitelist, licenses, source/portable split, private canaries and byte identity'
return $result
