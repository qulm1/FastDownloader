param([string]$Source,[string]$WorkRoot)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\WindowEngine.cs') -ReferencedAssemblies System.dll,System.Core.dll,System.Net.Http.dll,System.Web.Extensions.dll
. (Join-Path $PSScriptRoot '..\FastDownload.ps1') -LibraryOnly -StateDir (Join-Path $WorkRoot 'state') -DownloadDir (Join-Path $WorkRoot '下载 空格') -Source $Source -FileName 'fixture.bin'
$script:EnginePath = $script:Engine
$record = New-TaskRecord (Get-SourceSpec $Source) (Join-Path $WorkRoot '下载 空格')
[void][IO.Directory]::CreateDirectory($record.OutputDir)
[void][IO.Directory]::CreateDirectory($record.JobFolder)
$engine = $null
$evidence = New-Object System.Collections.ArrayList
function Await-Reply($Task) {
    if (-not $Task.Wait(5000)) { throw 'RPC timed out' }
    if (-not $Task.Result.Success) { throw $Task.Result.Error }
    return (ConvertFrom-Json -InputObject $Task.Result.Json).result
}
function Get-Snapshot {
    $snapshot = Await-Reply ($engine.PollAsync())
    $tasks = @($snapshot[1][0]) + @($snapshot[2][0]) + @($snapshot[3][0])
    return @($tasks | Where-Object { $null -ne $_ })
}
function Start-TestEngine {
    $port = [FastDownloader.WindowEngine]::FindPort()
    $secret = [Guid]::NewGuid().ToString('N')
    $arguments = @('--enable-rpc=true','--rpc-listen-all=false','--rpc-allow-origin-all=false',('--rpc-listen-port='+$port),('--rpc-secret='+$secret),'--auto-save-interval=1','--save-session-interval=1') +
        @(Get-AriaArguments $record | Where-Object { $_ -notmatch '^--(?:enable-rpc|auto-save-interval|save-session-interval)=' })
    $script:engine = New-Object FastDownloader.WindowEngine($script:EnginePath,[string[]]$arguments,$port,$secret)
    for ($i=0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 100
        $reply = $engine.PollAsync().Result
        if ($reply.Success) { return }
        if ($engine.Process.HasExited) { throw ('Engine exited '+$engine.Process.ExitCode) }
    }
    throw 'Engine startup timeout'
}
function Close-TestEngine {
    $null = Await-Reply ($engine.CommandAsync('aria2.shutdown'))
    if (-not $engine.Process.WaitForExit(12000)) { throw 'Graceful shutdown timeout' }
    $engine.Dispose(); $script:engine=$null
}
try {
    Start-TestEngine
    for ($i=0; $i -lt 80; $i++) {
        $tasks = @(Get-Snapshot)
        if (@($tasks | Where-Object { [long]$_.completedLength -gt 100000 }).Count -gt 0) { break }
        Start-Sleep -Milliseconds 100
    }
    if ($i -eq 80) { throw 'No real download progress' }
    $unauthenticated = $false
    try { Invoke-WebRequest -UseBasicParsing -Method Post -Uri ('http://127.0.0.1:'+$engine.Port+'/jsonrpc') -ContentType 'application/json' -Body '{"jsonrpc":"2.0","id":"check","method":"aria2.getGlobalStat","params":[]}' | Out-Null }
    catch { $unauthenticated = $true }
    if (-not $unauthenticated) { throw 'RPC accepted unauthenticated request' }
    $null = Await-Reply ($engine.CommandAsync('aria2.pauseAll'))
    for ($i=0; $i -lt 50; $i++) {
        $tasks = @(Get-Snapshot)
        if (@($tasks | Where-Object { $_.status -eq 'paused' }).Count -gt 0) { break }
        Start-Sleep -Milliseconds 100
    }
    if ($i -eq 50) { throw 'Pause did not take effect' }
    $before = [long]$tasks[0].completedLength
    Start-Sleep -Milliseconds 1400
    $after = [long](@(Get-Snapshot)[0].completedLength)
    if ($before -ne $after) { throw 'Paused bytes continued changing' }
    [void]$evidence.Add(@{name='Actual transfer / authenticated RPC / pause stable bytes';passed=$true;paused_bytes=$before})
    $null = Await-Reply ($engine.CommandAsync('aria2.unpauseAll'))
    for ($i=0; $i -lt 80; $i++) {
        $tasks = @(Get-Snapshot)
        if ([long]$tasks[0].completedLength -gt $before) { break }
        Start-Sleep -Milliseconds 100
    }
    if ($i -eq 80) { throw 'Resume did not advance bytes' }
    Close-TestEngine
    if (-not (Test-Path -LiteralPath (Join-Path $record.JobFolder 'unfinished.session'))) { throw 'Missing shutdown session' }
    [void]$evidence.Add(@{name='Resume advances bytes; graceful stop saves session';passed=$true})
    Start-TestEngine
    $null = Await-Reply ($engine.CommandAsync('aria2.unpauseAll'))
    for ($i=0; $i -lt 600; $i++) {
        $tasks = @(Get-Snapshot)
        if (@($tasks | Where-Object { $_.status -eq 'error' }).Count) { throw 'Restart transfer failed' }
        if (@($tasks | Where-Object { $_.status -eq 'complete' }).Count -gt 0) { break }
        Start-Sleep -Milliseconds 100
    }
    if ($i -eq 600) { throw 'Restart did not finish' }
    Close-TestEngine
    [void]$evidence.Add(@{name='New engine resumes saved state to completion';passed=$true;output=(Join-Path $record.OutputDir 'fixture.bin')})
    @{passed=$true;evidence=@($evidence);output=(Join-Path $record.OutputDir 'fixture.bin')} | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $WorkRoot 'window-engine-evidence.json') -Encoding UTF8
    Write-Output 'PASS: real window engine pause / resume / restart'
} finally {
    if ($null -ne $engine) {
        if (-not $engine.Process.HasExited) { $engine.Process.Kill(); $null=$engine.Process.WaitForExit(5000) }
        $engine.Dispose()
    }
}
