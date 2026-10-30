param([string]$NetworkSource,[string]$WorkRoot)
$ErrorActionPreference='Stop'
$testRoot=Join-Path $WorkRoot 'window-flow'
[void][IO.Directory]::CreateDirectory($testRoot)
. (Join-Path $PSScriptRoot '..\DownloadWindow.ps1') -LayoutOnly -StateDir (Join-Path $testRoot 'state') -DownloadDir (Join-Path $testRoot 'downloads')
$evidence=New-Object System.Collections.ArrayList
function Wait-Flow($Condition,[int]$Seconds=30) {
    $deadline=[DateTime]::Now.AddSeconds($Seconds)
    do {
        Update-Window
        if (& $Condition) { return }
        if ($status.Text -like '*失败*' -or $status.Text -like '*中断*') { throw $status.Text }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::Now -lt $deadline)
    throw ('Window flow timeout: '+$status.Text)
}
try {
    $renameBox.Text='window-flow.bin'
    Add-Inputs @($NetworkSource)
    Wait-Flow { $null -ne $script:Active -and $script:Active.Item.Record.PSObject.Properties['CompletedBytes'] -and $script:Active.Item.Record.CompletedBytes -gt 100000 }
    $item=$script:Active.Item
    $script:Active.Command=$script:Active.Engine.CommandAsync('aria2.pauseAll')
    Wait-Flow { $item.State -eq 'Paused' }
    $before=$item.Row.Cells['Done'].Value
    for($i=0;$i -lt 15;$i++){Update-Window;Start-Sleep -Milliseconds 100}
    if($item.Row.Cells['Done'].Value -ne $before){throw 'Window bytes changed while paused'}
    [void]$evidence.Add(@{name='Window backend shows paused state and stable bytes';passed=$true})
    Stop-Active 'Incomplete'
    Wait-Flow { $null -eq $script:Active }
    $saved=Get-Content -LiteralPath (Join-Path $item.Record.JobFolder 'task.json') -Raw | ConvertFrom-Json
    if($saved.Status -ne 'Incomplete' -or $saved.CompletedBytes -le 0){throw 'Stopped window flow did not preserve progress metadata'}
    [void]$evidence.Add(@{name='Graceful stop saves incomplete state and byte metadata';passed=$true})
    Set-ItemState $item 'Waiting'
    Wait-Flow { $null -ne $script:Active -and $item.State -in @('Paused','Downloading') }
    $script:Active.Command=$script:Active.Engine.CommandAsync('aria2.unpauseAll')
    Wait-Flow { $null -eq $script:Active -and $item.State -eq 'Completed' } 60
    $saved=Get-Content -LiteralPath (Join-Path $item.Record.JobFolder 'task.json') -Raw | ConvertFrom-Json
    if($saved.Status -ne 'Completed'){throw 'Window completion was not persisted'}
    if($saved.CompletedBytes -ne $saved.TotalBytes){throw 'Completed task retained an old partial progress checkpoint'}
    if($form.Visible){throw 'Test unexpectedly showed a desktop window'}
    [void]$evidence.Add(@{name='Window backend resumes to completed state without desktop input';passed=$true})
    @{passed=$true;kind='Hidden own-control/backend integration, actual local HTTP; not physical UI input';output=(Join-Path $item.Record.OutputDir 'window-flow.bin');checks=@($evidence)} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $testRoot 'flow-evidence.json') -Encoding UTF8
} finally {
    if($null -ne $script:Active){
        try{if(-not $script:Active.Engine.Process.HasExited){$null=$script:Active.Engine.CommandAsync('aria2.shutdown').Result;if(-not $script:Active.Engine.Process.WaitForExit(5000)){$script:Active.Engine.Process.Kill()}}}finally{$script:Active.Engine.Dispose();$script:Active.Lock.Dispose()}
    }
    $timer.Dispose();$tips.Dispose();$form.Dispose()
}
