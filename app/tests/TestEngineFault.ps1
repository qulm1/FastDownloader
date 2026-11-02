param([string]$WorkRoot = (Join-Path $env:TEMP 'FastDownloaderTests'))
$ErrorActionPreference = 'Stop'
[void][IO.Directory]::CreateDirectory($WorkRoot)
$work = Join-Path $WorkRoot ('engine-fault-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
. (Join-Path $PSScriptRoot '..\FastDownload.ps1') -LibraryOnly -StateDir (Join-Path $work 'state')
# Controlled child executable replacement returns aria2's disk-space failure code.
# No disk is filled, no system engine/dependency is removed or changed.
$faultEngine = Join-Path $work 'fault engine.cmd'
[IO.File]::WriteAllText($faultEngine, "@echo off`r`necho simulated insufficient disk space`r`nexit /b 9`r`n", [Text.Encoding]::ASCII)
$script:Engine = $faultEngine
$record = New-TaskRecord (Get-SourceSpec 'http://example.invalid/test-fixture.bin') (Join-Path $work 'output')
$code = Invoke-Task $record
if ($code -ne 9) { throw 'Did not preserve engine failure exit code' }
$saved = Get-Content -LiteralPath (Join-Path $record.JobFolder 'task.json') -Raw | ConvertFrom-Json
if ($saved.Status -ne 'Incomplete') { throw 'Disk-space failure must not complete task' }
@{ passed=$true; test='Injected disk-space engine failure'; actual_engine_transfer=$false; exit_code=$code; status=$saved.Status } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'evidence.json') -Encoding UTF8
Write-Output ('PASS: disk-space fault injection; evidence ' + $work)
